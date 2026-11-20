on run argv
	set volName to item 1 of argv
	tell application "Finder"
		tell disk volName
			open
			delay 0.5
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set bounds of container window to {400, 200, 940, 560}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 96
			set background picture of viewOptions to file ".background:background.png"
			set position of item "MicMute.app" of container window to {130, 170}
			set position of item "Applications" of container window to {410, 170}
			update without registering applications
			delay 1
			close
		end tell
	end tell
end run
