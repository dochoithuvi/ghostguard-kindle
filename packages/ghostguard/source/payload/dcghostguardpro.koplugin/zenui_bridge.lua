local logger = require("logger")

local ZenUIBridge = {}
ZenUIBridge.__index = ZenUIBridge

local HOME_ID = "dcpro_ghostguard.summary"

function ZenUIBridge:new(owner, plugin_dir)
    return setmetatable({
        owner = owner,
        plugin_dir = plugin_dir,
        registered = false,
        last_error = nil,
    }, self)
end

function ZenUIBridge:isAvailable()
    return type(rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")) == "function"
end

function ZenUIBridge:buildWidget(ctx)
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")

    local owner = self.owner
    local width = math.max(1, tonumber(ctx.width) or 1)
    local height = math.max(1, tonumber(ctx.height) or 1)
    local Screen = Device.screen
    local padding = math.max(4, Screen:scaleBySize(5))
    local inner_w = math.max(1, width - padding * 2)
    local inner_h = math.max(1, height - padding * 2)

    local title_face = Font:getFace("smallinfofont", Screen:scaleBySize(16))
    local status_face = Font:getFace("smallinfofont", Screen:scaleBySize(11))
    local hint_face = Font:getFace("smallinfofont", Screen:scaleBySize(8))

    local status = owner and owner.simpleUIPrimaryLabel and owner:simpleUIPrimaryLabel() or "GhostGuard"
    local licensed = owner and owner.guard and owner.guard:licenseValid(false)
    local license_text = licensed and "License: OK" or "License: chưa kích hoạt"
    local icon_size = math.min(
        math.max(28, math.floor(inner_h * 0.45)),
        math.max(28, math.floor(inner_w * 0.22))
    )

    if type(ctx.setWidgetActions) == "function" and owner then
        ctx.setWidgetActions{
            activate = function()
                owner:runSmartAction("zenui-home")
                return true
            end,
            context = function()
                owner:showStatus()
                return true
            end,
        }
    end

    local icon = IconWidget:new{
        file = self.plugin_dir .. "assets/ghostguard.svg",
        width = icon_size,
        height = icon_size,
        alpha = true,
    }

    local text_w = math.max(1, inner_w - icon_size - padding * 2)
    local column = VerticalGroup:new{
        TextWidget:new{
            text = "GhostGuard",
            face = title_face,
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        },
        VerticalSpan:new{ width = 2 },
        TextBoxWidget:new{
            text = tostring(status),
            face = status_face,
            width = text_w,
        },
        VerticalSpan:new{ width = 2 },
        TextWidget:new{
            text = license_text .. "  -  Chạm để thao tác",
            face = hint_face,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        },
    }

    local row = HorizontalGroup:new{
        align = "center",
        icon,
        HorizontalSpan:new{ width = padding },
        column,
    }

    return FrameContainer:new{
        width = width,
        height = height,
        padding = padding,
        bordersize = 1,
        color = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            row,
        },
    }
end

function ZenUIBridge:register()
    if self.registered then return true, "already-registered" end
    local register = rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")
    if type(register) ~= "function" then
        self.last_error = "Zen UI home registry unavailable"
        return false, self.last_error
    end

    local ok, result = pcall(register,
        HOME_ID,
        function(ctx) return self:buildWidget(ctx) end,
        {
            label = "GhostGuard",
            size = {
                preferred_pct = 0.16,
                min_pct = 0.12,
                max_pct = 0.24,
            },
        })
    if not ok or result == false then
        self.last_error = ok and "Zen UI rejected GhostGuard widget" or tostring(result)
        return false, self.last_error
    end

    self.registered = true
    self.last_error = nil
    logger.info("DCPRO GhostGuard registered Zen UI Home widget")
    return true, "registered"
end

function ZenUIBridge:unregister()
    local unregister = rawget(_G, "__ZEN_UI_UNREGISTER_HOME_ITEM")
    if type(unregister) == "function" then
        pcall(unregister, HOME_ID)
    end
    self.registered = false
    return true
end

function ZenUIBridge:statusText()
    if self.registered then return "HOME WIDGET ĐÃ ĐĂNG KÝ" end
    if self:isAvailable() then return "ZEN UI SẴN SÀNG - WIDGET CHƯA ĐĂNG KÝ" end
    return "ZEN UI KHÔNG HOẠT ĐỘNG"
end

return ZenUIBridge
