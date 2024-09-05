local data = require('data.min')
local battery = require('battery.min')
local camera = require('camera.min')

-- Phone to Frame flags
TAKE_PHOTO_MSG = 0x0d
TEXT_MSG = 0x0a

-- parse the take_photo message from the host into a table we can use with the camera_capture_and_send function
function parse_take_photo(data)
	local quality_values = {10, 25, 50, 100}
	local metering_values = {'SPOT', 'CENTER_WEIGHTED', 'AVERAGE'}

	local take_photo = {}
	-- quality and metering mode are indices into arrays of values (0-based phoneside; 1-based in Lua)
	-- exposure maps from 0..255 to -2.0..+2.0
	take_photo.quality = quality_values[string.byte(data, 1) + 1]
	take_photo.auto_exp_gain_times = string.byte(data, 2)
	take_photo.metering_mode = metering_values[string.byte(data, 3) + 1]
	take_photo.exposure = (string.byte(data, 4) - 128) / 64.0
	take_photo.shutter_kp = string.byte(data, 5) / 10.0
	take_photo.shutter_limit = string.byte(data, 6) << 8 | string.byte(data, 7)
	take_photo.gain_kp = string.byte(data, 8) / 10.0
	take_photo.gain_limit = string.byte(data, 9)
	return take_photo
end

-- parse the text message from the host
function parse_text(data)
	return data
end

-- register the message parser so it's automatically called when matching data comes in
data.parsers[TAKE_PHOTO_MSG] = parse_take_photo
data.parsers[TEXT_MSG] = parse_text

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
			if (data.app_data[TAKE_PHOTO_MSG] ~= nil) then
				rc, err = pcall(camera.camera_capture_and_send, data.app_data[TAKE_PHOTO_MSG])

				if rc == false then
					print(err)
				end
			end
			if (data.app_data[TEXT_MSG] ~= nil) then
				clear_display()
				print_text(data.app_data[TEXT_MSG])
			end
		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- run the main app loop
app_loop()