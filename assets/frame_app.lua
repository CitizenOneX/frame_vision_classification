local data = require('data.min')
local battery = require('battery.min')
local camera = require('camera.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
CAMERA_SETTINGS_MSG = 0x0d
TEXT_MSG = 0x0a

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAMERA_SETTINGS_MSG] = camera.parse_camera_settings
data.parsers[TEXT_MSG] = plain_text.parse_plain_text

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

-- draw the current text on the display
-- Note: For lower latency for text to first appear, we could draw the wip text as it arrives
-- keeping track of horizontal and vertical offsets to continue drawing subsequent packets
function print_text(text)
    local i = 0
    for line in text:gmatch("([^\n]*)\n?") do
        if line ~= "" then
            frame.display.text(line, 1, i * 60 + 1)
            i = i + 1
        end
    end
    frame.display.show()
end

-- Main app loop
function app_loop()
    local last_batt_update = 0
	clear_display()

	while true do
		-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
		local items_ready = data.process_raw_items()

		if items_ready > 0 then
			if (data.app_data[CAMERA_SETTINGS_MSG] ~= nil) then
				rc, err = pcall(camera.camera_capture_and_send, data.app_data[CAMERA_SETTINGS_MSG])

				if rc == false then
					print(err)
				end
			end
			if (data.app_data[TEXT_MSG] ~= nil) then
				clear_display()
				print_text(data.app_data[TEXT_MSG].string)
			end
		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- run the main app loop
app_loop()