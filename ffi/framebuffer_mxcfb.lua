local ffi = require("ffi")
local BB = require("ffi/blitbuffer")
local C = ffi.C

local dummy = require("ffi/posix_h")

-- Valid marker bounds
local MARKER_MIN = 42
local MARKER_MAX = (42 * 42)

local framebuffer = {
    -- pass device object here for proper model detection:
    device = nil,

    mech_wait_update_complete = nil,
    mech_wait_update_submission = nil,
    waveform_partial = nil,
    waveform_ui = nil,
    waveform_flashui = nil,
    waveform_full = nil,
    waveform_fast = nil,
    waveform_reagl = nil,
    mech_refresh = nil,
    -- start with an out of bound marker value to avoid doing something stupid on our first update
    marker = MARKER_MIN - 1,
}

--[[ refresh list management: --]]

-- Returns an incrementing marker value, w/ a sane wraparound.
function framebuffer:_get_next_marker()
    local marker = self.marker + 1
    if marker > MARKER_MAX then
        marker = MARKER_MIN
    end

    self.marker = marker
    return marker
end

-- Returns true if waveform_mode arg matches the UI waveform mode for current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, it's because of the Kindle-specific WAVEFORM_MODE_GC16_FAST
function framebuffer:_isUIWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_ui
end

-- Returns true if waveform_mode arg matches the FlashUI waveform mode for current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, it's because of the Kindle-specific WAVEFORM_MODE_GC16_FAST
function framebuffer:_isFlashUIWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_flashui
end

-- Returns true if waveform_mode arg matches the REAGL waveform mode for current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, it's Kindle's various WAVEFORM_MODE_REAGL vs. Kobo's NTX_WFM_MODE_GLD16
function framebuffer:_isREAGLWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_reagl
end

-- Returns true if w & h are equal or larger than our visible screen estate (i.e., we asked for a full-screen update)
function framebuffer:_isFullScreen(w, h)
    -- NOTE: fb:getWidth() & fb:getHeight() return the viewport size, but obey rotation, which means we can't rely on them directly.
    --       fb:getScreenWidth() & fb:getScreenHeight return the full screen size, without the viewport, and in the default rotation, which doesn't help either.
    -- Settle for getWidth() & getHeight() w/ rotation handling, like what bb:getPhysicalRect() does...
    if self:getRotationMode() % 2 == 1 then w, h = h, w end

    if w >= self:getWidth() and h >= self:getHeight() then
        return true
    else
        return false
    end
end

--[[ handlers for the wait API of the eink driver --]]

-- Kindle's MXCFB_WAIT_FOR_UPDATE_COMPLETE_PEARL == 0x4004462f
local function kindle_pearl_mxc_wait_for_update_complete(fb, marker)
    -- Wait for the previous update to be completed
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_PEARL, ffi.new("uint32_t[1]", marker))
end

-- Kobo's MXCFB_WAIT_FOR_UPDATE_COMPLETE_V1 == 0x4004462f
local function kobo_mxc_wait_for_update_complete(fb, marker)
    -- Wait for the previous update to be completed
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_V1, ffi.new("uint32_t[1]", marker))
end

-- Kobo's Mk7 MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3
local function kobo_mk7_mxc_wait_for_update_complete(fb, marker)
    -- Wait for the previous update to be completed
    local mk7_update_marker = ffi.new("struct mxcfb_update_marker_data[1]")
    mk7_update_marker[0].update_marker = marker
    -- NOTE: 0 seems to be a fairly safe assumption for "we don't care about collisions".
    --       On a slightly related note, the EPDC_FLAG_TEST_COLLISION flag is for dry-run collision tests, never set it.
    mk7_update_marker[0].collision_test = 0
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3, mk7_update_marker)
end

-- Kindle's MXCFB_WAIT_FOR_UPDATE_COMPLETE == 0x4004462f
local function pocketbook_mxc_wait_for_update_complete(fb, marker)
    -- Wait for the previous update to be completed
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, ffi.new("uint32_t[1]", marker))
end

-- Sony PRS MXCFB_WAIT_FOR_UPDATE_COMPLETE
local function sony_prstux_mxc_wait_for_update_complete(fb, marker)
    -- Wait for the previous update to be completed
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, ffi.new("uint32_t[1]", marker))
end

-- BQ Cervantes MXCFB_WAIT_FOR_UPDATE_COMPLETE == 0x4004462f
local function cervantes_mxc_wait_for_update_complete(fb, marker)
    -- Wait for the previous update to be completed
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, ffi.new("uint32_t[1]", marker))
end

-- Kindle's MXCFB_WAIT_FOR_UPDATE_COMPLETE == 0xc008462f
local function kindle_carta_mxc_wait_for_update_complete(fb, marker, collision_test)
    -- Wait for the previous update to be completed
    local carta_update_marker = ffi.new("struct mxcfb_update_marker_data[1]")
    carta_update_marker[0].update_marker = marker
    -- NOTE: 0 seems to be a fairly safe assumption for "we don't care about collisions".
    --       On a slightly related note, the EPDC_FLAG_TEST_COLLISION flag is for dry-run collision tests, never set it.
    carta_update_marker[0].collision_test = collision_test or 0
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, carta_update_marker)
end

-- Kindle's MXCFB_WAIT_FOR_UPDATE_SUBMISSION == 0x40044637
local function kindle_mxc_wait_for_update_submission(fb, marker)
    -- Wait for the current (the one we just sent) update to be submitted
    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_SUBMISSION, ffi.new("uint32_t[1]", marker))
end


--[[ refresh functions ]]--

-- Kindle's MXCFB_SEND_UPDATE == 0x4048462e
-- Kobo's MXCFB_SEND_UPDATE == 0x4044462e
-- Pocketbook's MXCFB_SEND_UPDATE == 0x4040462e
-- Cervantes MXCFB_SEND_UPDATE == 0x4044462e
local function mxc_update(fb, update_ioctl, refarea, refresh_type, waveform_mode, x, y, w, h)
    local bb = fb.full_bb or fb.bb
    w, x = BB.checkBounds(w or bb:getWidth(), x or 0, 0, bb:getWidth(), 0xFFFF)
    h, y = BB.checkBounds(h or bb:getHeight(), y or 0, 0, bb:getHeight(), 0xFFFF)
    x, y, w, h = bb:getPhysicalRect(x, y, w, h)

    if w == 0 or h == 0 then
        fb.debug("got a 0 size (height and/or width) refresh request, ignoring it.")
        return
    end

    if w == 1 and h == 1 then
        -- avoid system freeze when updating 1x1 pixel block on KPW2 and KV,
        -- see koreader/koreader#1299 and koreader/koreader#1486
        fb.debug("got a 1x1 pixel refresh request, ignoring it.")
        return
    end

    -- Pocketbook Color Lux refreshes based on bytes (not based on pixel)
    if fb.device:has3BytesWideFrameBuffer() then
       w = w*3
    end

    -- NOTE: If we're trying to send a:
    --         * true FULL update,
    --         * GC16_FAST update (i.e., popping-up a menu),
    --       then wait for submission of previous marker first.
    local marker = fb.marker
    -- NOTE: Technically, we might not always want to wait for *exactly* the previous marker
    --       (we might actually want the one before that), but in the vast majority of cases, that's good enough,
    --       and saves us a lot of annoying and hard-to-get-right heuristics anyway ;).
    -- Make sure it's a valid marker, to avoid doing something stupid on our first update.
    if (refresh_type == C.UPDATE_MODE_FULL
      or fb:_isUIWaveFormMode(waveform_mode))
      and fb.mech_wait_update_submission
      and (marker >= MARKER_MIN and marker <= MARKER_MAX) then
        fb.debug("refresh: wait for submission of (previous) marker", marker)
        fb.mech_wait_update_submission(fb, marker)
    end

    -- NOTE: If we're trying to send a:
    --         * REAGL update,
    --         * GC16 update,
    --         * Full-screen, flashing GC16_FAST update,
    --       then wait for completion of previous marker first.
    local collision_test = 0
    -- Again, make sure the marker is valid, too.
    if (fb:_isREAGLWaveFormMode(waveform_mode)
      or waveform_mode == C.WAVEFORM_MODE_GC16
      or (refresh_type == C.UPDATE_MODE_FULL and fb:_isFlashUIWaveFormMode(waveform_mode) and fb:_isFullScreen(w, h)))
      and fb.mech_wait_update_complete
      and (marker >= MARKER_MIN and marker <= MARKER_MAX) then
        -- NOTE: Disabled collision_test handling, because it's fragile, mysterious, easy to get wrong, hard to do right,
        --       and might change at a moment's notice, like the KOA2 proved...
        --[[
        -- NOTE: Setup the slightly mysterious collision_test flag...
        --       This is Kindle-only, but extra arguments are safely ignored in Lua ;).
        if fb:_isREAGLWaveFormMode(waveform_mode) then
            collision_test = 0
        elseif waveform_mode == C.WAVEFORM_MODE_GC16 or fb:_isFlashUIWaveFormMode(waveform_mode) then
            collision_test = 1642888
            -- On a KOA2:
            collision_test = 2126091812
        end
        -- NOTE: The KOA2 also sometimes (flashing? new menu?) waits on a previous (sometimes as far back as ~10 updates ago)
        --       "fast" (i.e., DU) marker, in which case collision is set to 1981826464
        --]]
        fb.debug("refresh: wait for completion of (previous) marker", marker, "with collision_test", collision_test)
        fb.mech_wait_update_complete(fb, marker, collision_test)
    end

    refarea[0].update_mode = refresh_type or C.UPDATE_MODE_PARTIAL
    refarea[0].waveform_mode = waveform_mode or C.WAVEFORM_MODE_GC16
    refarea[0].update_region.left = x
    refarea[0].update_region.top = y
    refarea[0].update_region.width = w
    refarea[0].update_region.height = h
    marker = fb:_get_next_marker()
    refarea[0].update_marker = marker
    -- NOTE: We're not using EPDC_FLAG_USE_ALT_BUFFER
    refarea[0].alt_buffer_data.phys_addr = 0
    refarea[0].alt_buffer_data.width = 0
    refarea[0].alt_buffer_data.height = 0
    refarea[0].alt_buffer_data.alt_update_region.top = 0
    refarea[0].alt_buffer_data.alt_update_region.left = 0
    refarea[0].alt_buffer_data.alt_update_region.width = 0
    refarea[0].alt_buffer_data.alt_update_region.height = 0

    -- Handle REAGL promotion...
    -- NOTE: We need to do this here, because we rely on the pre-promotion actual refresh_type in previous heuristics.
    if fb:_isREAGLWaveFormMode(waveform_mode) then
        -- NOTE: REAGL updates always need to be full.
        refarea[0].update_mode = C.UPDATE_MODE_FULL
    end

    -- Recap the actual details of the ioctl, vs. what UIManager asked for...
    fb.debug(string.format("mxc_update: %ux%u region @ (%u, %u) with marker %u (WFM: %u & UPD: %u)", w, h, x, y, marker, refarea[0].waveform_mode, refarea[0].update_mode))

    local rv = C.ioctl(fb.fd, update_ioctl, refarea)
    if rv < 0 then
        local err = ffi.errno()
        fb.debug("MXCFB_SEND_UPDATE ioctl failed:", ffi.string(C.strerror(err)))
    end

    -- NOTE: We wait for completion after *any kind* of full (i.e., flashing) update.
    if refarea[0].update_mode == C.UPDATE_MODE_FULL
      and fb.mech_wait_update_complete then
        --[[
        -- NOTE: Again, setup collision_test magic numbers...
        if fb:_isREAGLWaveFormMode(waveform_mode) then
            collision_test = 4
            -- On a KOA2:
            collision_test = 4096
        elseif waveform_mode == C.WAVEFORM_MODE_GC16 or fb:_isFlashUIWaveFormMode(waveform_mode) then
            collision_test = 1
            -- On a KOA2:
            collision_test = 4096
        end
        --]]
        fb.debug("refresh: wait for completion of marker", marker, "with collision_test", collision_test)
        fb.mech_wait_update_complete(fb, marker, collision_test)
    end
end

local function refresh_k51(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data[1]")
    -- only for Amazon's driver, try to mostly follow what the stock reader does...
    if waveform_mode == C.WAVEFORM_MODE_REAGL then
        -- If we're requesting WAVEFORM_MODE_REAGL, it's REAGL all around!
        refarea[0].hist_bw_waveform_mode = waveform_mode
        refarea[0].hist_gray_waveform_mode = waveform_mode
    else
        refarea[0].hist_bw_waveform_mode = C.WAVEFORM_MODE_DU
        refarea[0].hist_gray_waveform_mode = C.WAVEFORM_MODE_GC16_FAST
    end
    -- And we're only left with true full updates to special-case.
    if waveform_mode == C.WAVEFORM_MODE_GC16 then
        refarea[0].hist_gray_waveform_mode = waveform_mode
    end
    -- TEMP_USE_PAPYRUS on Touch/PW1, TEMP_USE_AUTO on PW2 (same value in both cases, 0x1001)
    refarea[0].temp = C.TEMP_USE_AUTO
    -- Enable the appropriate flag when requesting what amounts to a 2bit update
    if waveform_mode == C.WAVEFORM_MODE_DU then
        refarea[0].flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        refarea[0].flags = 0
    end
    -- TODO: EPDC_FLAG_ENABLE_INVERSION might be of use for NightMode,
    --       although the framework itself barely ever sets any flags, for some reason...

    return mxc_update(fb, C.MXCFB_SEND_UPDATE, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_koa2(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data_koa2[1]")
    -- only for Amazon's driver, try to mostly follow what the stock reader does...
    if waveform_mode == C.WAVEFORM_MODE_KOA2_GLR16 then
        -- If we're requesting WAVEFORM_MODE_KOA2_GLR16, it's REAGL all around!
        refarea[0].hist_bw_waveform_mode = waveform_mode
        refarea[0].hist_gray_waveform_mode = waveform_mode
    else
        refarea[0].hist_bw_waveform_mode = C.WAVEFORM_MODE_DU
        refarea[0].hist_gray_waveform_mode = C.WAVEFORM_MODE_GC16 -- NOTE: GC16_FAST points to GC16
    end
    -- NOTE: Since there's no longer a distinction between GC16_FAST & GC16, we're done!
    refarea[0].temp = C.TEMP_USE_AMBIENT
    refarea[0].dither_mode = C.EPDC_FLAG_USE_DITHERING_PASSTHROUGH
    refarea[0].quant_bit = 0;
    -- Enable the appropriate flag when requesting what amounts to a 2bit update
    if waveform_mode == C.WAVEFORM_MODE_DU then
        refarea[0].flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        refarea[0].flags = 0
    end
    -- TODO: There's also the HW-backed NightMode which should be somewhat accessible...

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_KOA2, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_kobo(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data_v1_ntx[1]")
    -- only for Kobo's driver:
    refarea[0].alt_buffer_data.virt_addr = nil
    -- TEMP_USE_AMBIENT, not that there was ever any other choice on Kobo...
    refarea[0].temp = C.TEMP_USE_AMBIENT
    -- Enable the appropriate flag when requesting a REAGLD waveform (NTX_WFM_MODE_GLD16 on the Aura)
    if waveform_mode == C.NTX_WFM_MODE_GLD16 then
        refarea[0].flags = C.EPDC_FLAG_USE_AAD
    elseif waveform_mode == C.WAVEFORM_MODE_A2 then
        -- As well as when requesting a 2bit waveform
        refarea[0].flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        refarea[0].flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_V1_NTX, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_kobo_mk7(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data_v2[1]")
    -- TEMP_USE_AMBIENT, not that there was ever any other choice on Kobo...
    refarea[0].temp = C.TEMP_USE_AMBIENT
    refarea[0].dither_mode = C.EPDC_FLAG_USE_DITHERING_PASSTHROUGH
    refarea[0].quant_bit = 0;
    -- Enable the appropriate flag when requesting a 2bit update
    -- NOTE: As of right now (FW 4.9.x), WAVEFORM_MODE_GLD16 appears not to be used by Nickel,
    --       so we don't have to care about EPDC_FLAG_USE_REGAL
    if waveform_mode == C.WAVEFORM_MODE_A2 then
        refarea[0].flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        refarea[0].flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_V2, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_pocketbook(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data[1]")
    -- TEMP_USE_AMBIENT
    refarea[0].temp = 0x1000

    return mxc_update(fb, C.MXCFB_SEND_UPDATE, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_sony_prstux(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data[1]")
    refarea[0].temp = C.TEMP_USE_AMBIENT
    return mxc_update(fb, C.MXCFB_SEND_UPDATE, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_cervantes_old(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data[1]")
    refarea[0].alt_buffer_data.virt_addr = nil
    refarea[0].temp = C.TEMP_USE_AMBIENT

    if waveform_mode == C.WAVEFORM_MODE_A2 then
        refarea[0].flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        refarea[0].flags = 0
    end
    return mxc_update(fb, C.MXCFB_SEND_UPDATE_OLD, refarea, refreshtype, waveform_mode, x, y, w, h)
end

local function refresh_cervantes(fb, refreshtype, waveform_mode, x, y, w, h)
    local refarea = ffi.new("struct mxcfb_update_data[1]")
    refarea[0].temp = C.TEMP_USE_AMBIENT
    return mxc_update(fb, C.MXCFB_SEND_UPDATE, refarea, refreshtype, waveform_mode, x, y, w, h)
end


--[[ framebuffer API ]]--

function framebuffer:refreshPartialImp(x, y, w, h)
    self.debug("refresh: partial", x, y, w, h)
    self:mech_refresh(C.UPDATE_MODE_PARTIAL, self.waveform_partial, x, y, w, h)
end

-- NOTE: UPDATE_MODE_FULL doesn't mean full screen or no region, it means ask for a black flash!
--       The only exception to that rule is with REAGL waveform modes, where it will *NOT* flash.
--       But then, REAGL waveform modes will *never* use anything other than FULL update mode anyway ;).
function framebuffer:refreshFlashPartialImp(x, y, w, h)
    self.debug("refresh: partial w/ flash", x, y, w, h)
    self:mech_refresh(C.UPDATE_MODE_FULL, self.waveform_partial, x, y, w, h)
end

function framebuffer:refreshUIImp(x, y, w, h)
    self.debug("refresh: ui-mode", x, y, w, h)
    self:mech_refresh(C.UPDATE_MODE_PARTIAL, self.waveform_ui, x, y, w, h)
end

function framebuffer:refreshFlashUIImp(x, y, w, h)
    self.debug("refresh: ui-mode w/ flash", x, y, w, h)
    self:mech_refresh(C.UPDATE_MODE_FULL, self.waveform_flashui, x, y, w, h)
end

function framebuffer:refreshFullImp(x, y, w, h)
    self.debug("refresh: full", x, y, w, h)
    self:mech_refresh(C.UPDATE_MODE_FULL, self.waveform_full, x, y, w, h)
end

function framebuffer:refreshFastImp(x, y, w, h)
    self.debug("refresh: fast", x, y, w, h)
    self:mech_refresh(C.UPDATE_MODE_PARTIAL, self.waveform_fast, x, y, w, h)
end

function framebuffer:init()
    framebuffer.parent.init(self)

    self.refresh_list = {}

    if self.device:isKindle() then
        require("ffi/mxcfb_kindle_h")

        self.mech_refresh = refresh_k51
        self.mech_wait_update_complete = kindle_pearl_mxc_wait_for_update_complete
        self.mech_wait_update_submission = kindle_mxc_wait_for_update_submission

        self.waveform_fast = C.WAVEFORM_MODE_A2
        self.waveform_ui = C.WAVEFORM_MODE_GC16_FAST
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16

        -- New devices are REAGL-aware, default to REAGL
        local isREAGL = true

        -- The KOA2 uses a new eink driver, one that massively breaks backward compatibility.
        local isKOA2 = false

        if self.device.model == "Kindle2" then
            isREAGL = false
        elseif self.device.model == "KindleDXG" then
            isREAGL = false
        elseif self.device.model == "Kindle3" then
            isREAGL = false
        elseif self.device.model == "Kindle4" then
            isREAGL = false
        elseif self.device.model == "KindleTouch" then
            isREAGL = false
        elseif self.device.model == "KindlePaperWhite" then
            isREAGL = false
        end

        if self.device.model == "KindleOasis2" then
            isKOA2 = true
        end

        if isREAGL then
            self.mech_wait_update_complete = kindle_carta_mxc_wait_for_update_complete
            self.waveform_fast = C.WAVEFORM_MODE_DU -- NOTE: DU, because A2 looks terrible on REAGL devices. Older devices/FW may be using AUTO in this instance.
            self.waveform_reagl = C.WAVEFORM_MODE_REAGL
            self.waveform_partial = self.waveform_reagl
        else
            self.waveform_partial = C.WAVEFORM_MODE_GL16_FAST -- NOTE: Depending on FW, might instead be AUTO w/ hist_gray_waveform_mode set to GL16_FAST
        end

        if isKOA2 then
            self.mech_refresh = refresh_koa2

            self.waveform_fast = C.WAVEFORM_MODE_DU
            self.waveform_ui = C.WAVEFORM_MODE_AUTO
            -- NOTE: Possibly to bypass the possibility that AUTO, even when FULL, might not flash (something which holds true for a number of devices, especially on small regions),
            --       The KOA2 explicitly requests GC16 when flashing an UI element that doesn't cover the full screen...
            --       And it resorts to AUTO when PARTIAL, because GC16_FAST is no more (it points to GC16).
            self.waveform_flashui = C.WAVEFORM_MODE_GC16
            self.waveform_reagl = C.WAVEFORM_MODE_KOA2_GLR16
            self.waveform_partial = self.waveform_reagl
        end
    elseif self.device:isKobo() then
        require("ffi/mxcfb_kobo_h")

        self.mech_refresh = refresh_kobo
        self.mech_wait_update_complete = kobo_mxc_wait_for_update_complete

        self.waveform_fast = C.WAVEFORM_MODE_A2
        self.waveform_ui = C.WAVEFORM_MODE_AUTO
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.NTX_WFM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_AUTO

        -- New devices *may* be REAGL-aware, but generally don't expect explicit REAGL requests, default to not.
        local isREAGL = false

        -- Mark 7 devices sport an updated driver.
        -- For now, it appears backward compatibility has been somewhat preserved,
        -- but let's use the shiny new stuff!
        local isMk7 = false

        -- NOTE: AFAICT, the Aura was the only one explicitly requiring REAGL requests...
        if self.device.model == "Kobo_phoenix" then
            isREAGL = true
        end

        if self.device.model == "KoboStarRev2" then
            isMk7 = true
        elseif self.device.model == "KoboSnowRev2" then
            isMk7 = true
        elseif self.device.model == "KoboNova" then
            isMk7 = true
        end

        if isREAGL then
            self.waveform_reagl = C.NTX_WFM_MODE_GLD16
            self.waveform_partial = self.waveform_reagl
            self.waveform_fast = C.WAVEFORM_MODE_DU -- Mainly menu HLs, compare to Kindle's use of AUTO or DU also in these instances ;).
        end

        -- NOTE: There's a fun twist to Mark 7 devices:
        --       they do use GLR16 update modes (i.e., REAGL), but they do NOT need/do the PARTIAL -> FULL trick...
        --       We handle that by NOT setting waveform_reagl (so _isREAGLWaveFormMode never matches), and just customizing waveform_partial.
        --       Nickel doesn't wait for completion of previous markers on those PARTIAL GLR16, so that's enough to keep our heuristics intact,
        --       while still doing the right thing everywhere ;).
        if isMk7 then
            self.mech_refresh = refresh_kobo_mk7
            self.mech_wait_update_complete = kobo_mk7_mxc_wait_for_update_complete

            self.waveform_partial = C.WAVEFORM_MODE_GLR16
            -- NOTE: DU may rarely be used instead of A2 by Nickel, but never w/ the MONOCHROME flag, so, keep using A2 everywhere on our end.
        end
    elseif self.device:isPocketBook() then
        require("ffi/mxcfb_pocketbook_h")

        self.mech_refresh = refresh_pocketbook
        self.mech_wait_update_complete = pocketbook_mxc_wait_for_update_complete

        self.waveform_fast = C.WAVEFORM_MODE_A2
        self.waveform_ui = C.WAVEFORM_MODE_GC16
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_GC16
    elseif self.device:isSonyPRSTUX() then
        require("ffi/mxcfb_sony_h")

        self.mech_refresh = refresh_sony_prstux
        self.mech_wait_update_complete = sony_prstux_mxc_wait_for_update_complete

        self.waveform_fast = C.WAVEFORM_MODE_DU
        self.waveform_ui = C.WAVEFORM_MODE_AUTO
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_AUTO
    elseif self.device:isCervantes() then
        require("ffi/mxcfb_cervantes_h")

        self.mech_refresh = refresh_cervantes_old
        self.mech_wait_update_complete = cervantes_mxc_wait_for_update_complete

        self.waveform_fast = C.WAVEFORM_MODE_A2
        self.waveform_ui = C.WAVEFORM_MODE_AUTO
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_AUTO

        -- new devices
        local is_new = false
        if self.device.model == "Cervantes2013" or self.device.model == "Cervantes3"
            or self.device.model == "Cervantes4" then is_new = true end

        if is_new then
            self.mech_refresh = refresh_cervantes
            self.waveform_fast = C.WAVEFORM_MODE_DU
            self.waveform_reagl = C.WAVEFORM_MODE_GLD16
            self.waveform_partial = self.waveform_reagl
        end
    else
        error("unknown device type")
    end
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
