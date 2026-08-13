local ffi = require("ffi")
pcall(require, "ffi/loadlib")

ffi.cdef[[
typedef struct bio_st BIO;
typedef struct evp_pkey_st EVP_PKEY;
typedef struct evp_md_st EVP_MD;
typedef struct evp_md_ctx_st EVP_MD_CTX;
typedef struct evp_pkey_ctx_st EVP_PKEY_CTX;
typedef struct engine_st ENGINE;
BIO *BIO_new_mem_buf(const void *buf, int len);
int BIO_free(BIO *a);
EVP_PKEY *PEM_read_bio_PUBKEY(BIO *bp, EVP_PKEY **x, void *cb, void *u);
void EVP_PKEY_free(EVP_PKEY *pkey);
EVP_MD_CTX *EVP_MD_CTX_new(void);
void EVP_MD_CTX_free(EVP_MD_CTX *ctx);
const EVP_MD *EVP_sha256(void);
int EVP_DigestVerifyInit(EVP_MD_CTX *ctx, EVP_PKEY_CTX **pctx, const EVP_MD *type, ENGINE *e, EVP_PKEY *pkey);
int EVP_DigestVerifyUpdate(EVP_MD_CTX *ctx, const void *d, size_t cnt);
int EVP_DigestVerifyFinal(EVP_MD_CTX *ctx, const unsigned char *sig, size_t siglen);
int EVP_Digest(const void *data, size_t count, unsigned char *md, unsigned int *size, const EVP_MD *type, ENGINE *impl);
]]

local M = {}
local crypto_lib

local function load_crypto()
    if crypto_lib then return crypto_lib end
    local ok, lib
    if ffi.loadlib then
        -- Current KOReader uses crypto ABI 57. Keep 56/55 fallbacks for older
        -- supported KOReader bundles, and finally try an unversioned libcrypto.
        ok, lib = pcall(ffi.loadlib,
            "crypto", "57",
            "crypto", "56",
            "crypto", "55",
            "crypto", nil)
    end
    if not ok then ok, lib = pcall(ffi.load, "crypto") end
    if not ok or not lib then return nil, "LIBCRYPTO_UNAVAILABLE" end
    crypto_lib = lib
    return crypto_lib
end

local B64 = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do B64[alphabet:sub(i,i)] = i - 1 end
end

function M.base64Decode(input)
    input = tostring(input or ""):gsub("%s", "")
    if input == "" or (#input % 4) ~= 0 then return nil, "SIGNATURE_BASE64_INVALID" end
    local out = {}
    for i = 1, #input, 4 do
        local a,b,c,d = input:sub(i,i), input:sub(i+1,i+1), input:sub(i+2,i+2), input:sub(i+3,i+3)
        local va,vb = B64[a], B64[b]
        if va == nil or vb == nil then return nil, "SIGNATURE_BASE64_INVALID" end
        local vc = c == "=" and 0 or B64[c]
        local vd = d == "=" and 0 or B64[d]
        if vc == nil or vd == nil then return nil, "SIGNATURE_BASE64_INVALID" end
        local n = va * 262144 + vb * 4096 + vc * 64 + vd
        out[#out+1] = string.char(math.floor(n / 65536) % 256)
        if c ~= "=" then out[#out+1] = string.char(math.floor(n / 256) % 256) end
        if d ~= "=" then out[#out+1] = string.char(n % 256) end
        if c == "=" and d ~= "=" then return nil, "SIGNATURE_BASE64_INVALID" end
        if (c == "=" or d == "=") and i ~= #input - 3 then return nil, "SIGNATURE_BASE64_INVALID" end
    end
    return table.concat(out)
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function M.verify(public_key_path, message, signature_b64)
    local lib, err = load_crypto()
    if not lib then return false, err end
    local pem = read_file(public_key_path)
    if not pem or pem == "" then return false, "PUBLIC_KEY_MISSING" end
    local sig, sigerr = M.base64Decode(signature_b64)
    if not sig then return false, sigerr end

    local bio = lib.BIO_new_mem_buf(pem, #pem)
    if bio == nil then return false, "PUBLIC_KEY_BIO_FAILED" end
    local pkey = lib.PEM_read_bio_PUBKEY(bio, nil, nil, nil)
    lib.BIO_free(bio)
    if pkey == nil then return false, "PUBLIC_KEY_PARSE_FAILED" end

    local ctx = lib.EVP_MD_CTX_new()
    if ctx == nil then
        lib.EVP_PKEY_free(pkey)
        return false, "VERIFY_CTX_FAILED"
    end

    local ok = lib.EVP_DigestVerifyInit(ctx, nil, lib.EVP_sha256(), nil, pkey) == 1
    if ok then ok = lib.EVP_DigestVerifyUpdate(ctx, message, #message) == 1 end
    if ok then ok = lib.EVP_DigestVerifyFinal(ctx, sig, #sig) == 1 end

    lib.EVP_MD_CTX_free(ctx)
    lib.EVP_PKEY_free(pkey)
    return ok, ok and "RSA_SHA256_VALID" or "SIGNATURE_MISMATCH"
end


function M.sha256Hex(message)
    local lib, err = load_crypto()
    if not lib then return nil, err end
    message = tostring(message or "")
    local out = ffi.new("unsigned char[32]")
    local outlen = ffi.new("unsigned int[1]")
    local ok = lib.EVP_Digest(message, #message, out, outlen, lib.EVP_sha256(), nil) == 1
    if not ok or tonumber(outlen[0]) ~= 32 then return nil, "SHA256_FAILED" end
    local parts = {}
    for i = 0, 31 do parts[#parts+1] = string.format("%02x", tonumber(out[i])) end
    return table.concat(parts)
end

return M
