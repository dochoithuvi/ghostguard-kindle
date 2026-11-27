-- Reader gesture profile: receives only completed, accepted IntentShield strokes.
local P = {}
function P.action(v, w, h)
    if not v.compatible then return end
    local dx,dy=math.abs(v.dx),math.abs(v.dy)
    if v.y0>=h*0.86 and v.x0>w*0.25 and v.x1>w*0.25 and v.dy<=-300 and dy>=3*dx then
        return 'PANEL'
    end
    -- Deliberate upward-right diagonal, ending on the desired word.
    if v.dx>=90 and v.dy<=-90 and dx/dy>=0.65 and dx/dy<=1.55
        and v.net>=140 and v.net<=320 and v.duration>=230000
        and v.straight>=0.88 and v.y0<h*0.86 and v.y1>h*0.08 then
        return 'DICT'
    end
end
function P.openPanel(reader, Event)
    -- ZenOS 4.3.x extends this native KOReader event with an initial tab.
    if reader.thumbnail and type(reader.thumbnail.onShowPageBrowser)=='function' then
        reader:handleEvent(Event:new('ShowPageBrowser','aa'))
        return true
    end
    if reader.menu and type(reader.menu.onShowReaderControls)=='function' then
        return reader.menu:onShowReaderControls()
    end
    return reader:handleEvent(Event:new('ShowConfigMenu'))
end
function P.lookup(reader, v, Geom)
    -- Initial beta: text-based reflowable books only; no touch/hold injection.
    if not reader.rolling or not reader.document or not reader.view or not reader.dictionary then return false end
    if type(reader.document.getWordFromPosition)~='function' or type(reader.view.screenToPageTransform)~='function'
        or type(reader.dictionary.onLookupWord)~='function' then return false end
    local pos=reader.view:screenToPageTransform(Geom:new{x=v.x1,y=v.y1,w=0,h=0})
    if not pos then return false end
    local ok, word=pcall(reader.document.getWordFromPosition,reader.document,pos,true)
    if not ok or type(word)~='table' or type(word.word)~='string' or not word.word:match('%S') then return false end
    local boxes
    if word.sbox and type(reader.view.pageToScreenTransform)=='function' then
        local bok,box=pcall(reader.view.pageToScreenTransform,reader.view,pos.page,word.sbox)
        if bok and box then boxes={box} end
    end
    reader.dictionary:onLookupWord(word.word,false,boxes)
    return true
end
return P
