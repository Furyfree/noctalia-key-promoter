--!nonstrict
-- The desktop bind list the snippet wrote from the real nix config, 2026-10-25.
return [=[
SUPER + Return	Open Ghostty terminal	uwsm-app -- ghostty +new-window		
SUPER + SHIFT + B	Open Brave browser	uwsm-app -- brave-origin		
SUPER + SHIFT + P	Focus or open 1Password	uwsm-app -- 1password		
CTRL + SHIFT + Space	Open 1Password Quick Access	uwsm-app -- 1password --quick-access		
SUPER + SHIFT + F	Open file manager	uwsm-app -- nautilus		
SUPER + ALT + F	Open file manager in the terminal's folder	launch nautilus-cwd		
SUPER + ALT + Return	Open floating terminal	launch floating-terminal		
SUPER + SHIFT + O	Focus or open Obsidian			
SUPER + SHIFT + D	Focus or open Discord in Vesktop			
SUPER + SHIFT + G	Focus or open Signal			
SUPER + SHIFT + E	Focus or open Fastmail			
SUPER + SHIFT + Z	Open Zed	uwsm-app -- zeditor		
SUPER + SHIFT + V	Open VSCodium	uwsm-app -- codium		
SUPER + SHIFT + T	Focus or open T3 Code			
SUPER + W	Close focused window			
SUPER + Q	Toggle floating window			
SUPER + Space	Open Noctalia launcher	noctalia msg panel-toggle launcher		
SUPER + V	Open clipboard history	noctalia msg panel-toggle clipboard		
SUPER + O	Toggle workspace overview on all monitors			
SUPER + SHIFT + N	Open notification centre	noctalia msg panel-toggle control-center notifications		
SUPER + comma	Toggle Noctalia settings	noctalia msg settings-toggle		
SUPER + SHIFT + W	Open wallpaper browser	noctalia msg panel-toggle wallpaper		
SUPER + CTRL + C	Open crash history and diagnostics	noctalia msg panel-toggle umedbazarov/crashes:panel		
SUPER + Escape	Open keybind cheatsheet	noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet		
SUPER + CTRL + G	Open Git Companion	noctalia msg panel-toggle tphilippot/git_companion:main		
SUPER + CTRL + D	Open Docker manager	noctalia msg panel-toggle 8bury/mini-docker:manager		
SUPER + CTRL + P	Open port manager	noctalia msg panel-toggle rxtsel/portctl:panel		
SUPER + CTRL + M	Open screen mirroring	noctalia msg panel-toggle profidev/hypr-screen-mirror:panel		
SUPER + CTRL + N	Open notes	noctalia msg panel-toggle noctalia/notes:panel		
SUPER + CTRL + S	Open SSH launcher	noctalia msg panel-toggle launcher '/ssh '		
SUPER + CTRL + B	Open btop	launch tui btop		
SUPER + CTRL + Y	Open Yazi	launch tui yazi		
SUPER + ALT + L	Toggle workspace layout: Dwindle / Scrolling			
SUPER + R	Scrolling: cycle column width			
SUPER + C	Scrolling: center column			
SUPER + J	Dwindle: toggle split orientation			
SUPER + F	Scrolling: half/full width; Dwindle: maximize/restore			
SUPER + SHIFT + Return	Toggle fullscreen			
SUPER + minus	Narrow window			
SUPER + SHIFT + minus	Shorten window			
SUPER + plus	Widen window			
SUPER + SHIFT + plus	Taller window			
SUPER + ALT + left	Scrolling: join/separate window toward left			
SUPER + ALT + right	Scrolling: join/separate window toward right			
SUPER + L	Lock session	noctalia msg session lock		
SUPER + SHIFT + L	Open Noctalia session menu	noctalia msg panel-toggle session		
SUPER + Tab	Open Noctalia window picker	noctalia msg window-switcher		
ALT + Tab	Return to last workspace on this monitor			
SUPER + SHIFT + S	Capture screen region	noctalia msg screenshot-region		
Print	Capture screen region	noctalia msg screenshot-region		
SHIFT + Print	Capture current monitor	noctalia msg screenshot-fullscreen		
XF86AudioRaiseVolume	Increase volume	noctalia msg volume-up		
XF86AudioLowerVolume	Decrease volume	noctalia msg volume-down		
XF86MonBrightnessUp	Increase brightness	noctalia msg brightness-up		
XF86MonBrightnessDown	Decrease brightness	noctalia msg brightness-down		
XF86AudioMute	Toggle speaker mute	noctalia msg volume-mute		
XF86AudioMicMute	Toggle microphone mute	noctalia msg mic-mute		
XF86AudioPrev	Previous track	noctalia msg media previous		
XF86AudioPlay	Play/pause	noctalia msg media toggle		
XF86AudioNext	Next track	noctalia msg media next		
XF86LaunchA	NuPhy F3: toggle workspace overview			
XF86VoiceCommand	NuPhy F5: toggle microphone mute	noctalia msg mic-mute		
XF86DoNotDisturb	NuPhy F6: toggle Do Not Disturb	noctalia msg notification-dnd-toggle		
SUPER + D	Dictation: start or stop recording	voxtype record toggle		
SUPER + SHIFT + Escape	Dictation: cancel recording	voxtype record cancel		
SUPER + left	Focus window left			
SUPER + CTRL + left	Focus monitor and pointer left			
SUPER + SHIFT + left	Swap window on this monitor left			
SUPER + SHIFT + CTRL + left	Move window to monitor left			
SUPER + right	Focus window right			
SUPER + CTRL + right	Focus monitor and pointer right			
SUPER + SHIFT + right	Swap window on this monitor right			
SUPER + SHIFT + CTRL + right	Move window to monitor right			
SUPER + up	Focus window up			
SUPER + CTRL + up	Focus monitor and pointer up			
SUPER + SHIFT + up	Swap window on this monitor up			
SUPER + SHIFT + CTRL + up	Move window to monitor up			
SUPER + down	Focus window down			
SUPER + CTRL + down	Focus monitor and pointer down			
SUPER + SHIFT + down	Swap window on this monitor down			
SUPER + SHIFT + CTRL + down	Move window to monitor down			
SUPER + ALT + up	Switch workspace up on this monitor			
SUPER + SHIFT + ALT + up	Move window to workspace up and follow			
SUPER + ALT + down	Switch workspace down on this monitor			
SUPER + SHIFT + ALT + down	Move window to workspace down and follow			
SUPER + 1	Switch to local workspace 1			
SUPER + SHIFT + 1	Move window to local workspace 1			
SUPER + 2	Switch to local workspace 2			
SUPER + SHIFT + 2	Move window to local workspace 2			
SUPER + 3	Switch to local workspace 3			
SUPER + SHIFT + 3	Move window to local workspace 3			
SUPER + 4	Switch to local workspace 4			
SUPER + SHIFT + 4	Move window to local workspace 4			
SUPER + 5	Switch to local workspace 5			
SUPER + SHIFT + 5	Move window to local workspace 5			
SUPER + 6	Switch to local workspace 6			
SUPER + SHIFT + 6	Move window to local workspace 6			
SUPER + 7	Switch to local workspace 7			
SUPER + SHIFT + 7	Move window to local workspace 7			
SUPER + 8	Switch to local workspace 8			
SUPER + SHIFT + 8	Move window to local workspace 8			
SUPER + 9	Switch to local workspace 9			
SUPER + SHIFT + 9	Move window to local workspace 9			
SUPER + 0	Switch to local workspace 10			
SUPER + SHIFT + 0	Move window to local workspace 10			
]=]
