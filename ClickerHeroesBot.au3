#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>

HotKeySet ( "{ESC}", "Terminate" )

$winTitle = "Clicker Heroes"

; == constant definitions ==

; default window size
Const $winSizeDefault[2] = [1152, 679]

; click position
Const $posClick[2] = [865, 375]

; next level check
Const $posCheckNextLevel[2] = [925, 55]
Const $colorCheckNextLevel = 0xFFDB2C
Const $colorCheckNextLevelVar = 16
Const $posPreviousLevel[2] = [795, 75]
Const $rectHasNextLevel[4] = [915, 90, 930, 100]
Const $rectHasNextLevelSkip = 4 ; skip to every 4th pixel while checking; adjust if has next level detection fails
Const $colorHasNextLevel = 0xFE9800
Const $colorHasNextLevelVar = 16

; general check vars
Const $timeCheckInterval = 200 ; 0.2 sec

; health check
Const $posHealthCheck[2] = [801, 582]
Const $colorHealthCheckNearDeath = 0xF60000
Const $colorHealthCheckHalf = 0xFB5B00
Const $colorHealthCheckQuarter = 0xB8BE00
Const $colorHealthCheckFull = 0x45BF00
Const $colorHealthCheckBarEmpty = 0x413F3F

; boss check
Const $posBossCheck[2] = [832, 197]
Const $colorBossCheck = 0xBAD2E2
Const $timeBossCheckInterval = 8000 ; 8 sec
Const $timeBossRetryInterval = 600000 ; 10 minutes
Const $timeBossLevelTimer = 35000 ; 35 sec
Const $timeBossRetryPreLevelSpeed = 2300 ;2.3 sec - according to many people online

; spells
; 1 = auto click
; 2 = bonus DPS
Const $spellActivationOrder = "213"

; fish check
Const $colorFishLeaf = 0xB4C523
Const $colorFishStick = 0x3F2105
Const $colorFishMouth = 0xF29F09
Const $timeFishCheck = 60000 ; 1 minute

; scrollbar
Const $posScrollbarButton[2] = [555, 655]
Const $posScrollbarButtonUp[2] = [555, 220]
Const $posScrollbarCheck[2] = [555, 640]
Const $posScrollbarCheckUp[2] = [555, 234]
Const $colorScrollbarNoBar = 0x422904
Const $colorScrollbarBar = 0xFFEC8C

; level up
Const $timeLevelUpTimer = 120000 ; 2 minutes
Const $timeLevelUpMax = 30000 ; 30 sec
Const $rectLevelUp[4] = [90, 203, 91, 670]
Const $colorLevelUp = 0x5DBDFF
Const $countScrollRetries = 30

; == wait for window ==
WinWaitActive( $winTitle, "", 60)

; == active variable definitions ==
Global $winPos = WinGetPos( $winTitle ) ; get window pos and size
Global $hwnd = WinGetProcess( $winTitle ) ; get the process handle

; initialize runtime variables
Global $hasBossLevel = False
Global $isBossLevel = False
Global $timeRequiredReset = 99999
Global $timeRequired = $timeRequiredReset ; fake some time greater than the limit specified above
Global $mayDetectDead = False

; initialize timers
Global $bossLevelCheckTimer = False ; not running
Global $bossLevelTimer = False ; not running
Global $bossRetryTimer = False ; not running
Global $fullHealthTimer = False ; not running
Global $checkTimer = TimerInit()
Global $levelUpTimer = TimerInit()
Global $fishTimer = TimerInit()

; run checks once in the beginning
TimedCheck()
CheckForFish()

; == main loop ==
While True
	; run checks if timer is up
	If TimerDiff( $checkTimer ) > $timeCheckInterval Then
		TimedCheck()
		$checkTimer = TimerInit() ; reset timer
	EndIf

	If Not $isBossLevel And TimerDiff( $levelUpTimer ) > $timeLevelUpTimer Then
		DoLevelUps()
		$levelUpTimer = TimerInit() ; reset timer
	EndIf

	If Not $isBossLevel And TimerDiff( $fishTimer ) > $timeFishCheck Then
		CheckForFish()
		$fishTimer = TimerInit() ; reset timer
	EndIf

	If $fullHealthTimer <> False Then
		If $mayDetectDead And $timeRequired == $timeRequiredReset And CheckHealthDead() Then
			$timeRequired = TimerDiff( $fullHealthTimer ) - 500 ; get required time - correct time because of checking method
			$mayDetectDead = False
			Debug("monster killed within " & Round( $timeRequired / 1000, 2 ) & " seconds")
			; check if monster is dead within specified time frame
			If $timeRequired <= $timeBossRetryPreLevelSpeed Then
				Debug("good time! trying the boss")
				$fullHealthTimer = False ; disable timer
				; we may proceed to the boss level
				$bossRetryTimer = False
				$hasBossLevel = False
			EndIf
		EndIf
	EndIf

	If Not $mayDetectDead And Not CheckHealthDead() Then
		; reset timer
		$fullHealthTimer = TimerInit()
		$timeRequired = $timeRequiredReset
		$mayDetectDead = True
	EndIf

	; click that monster!
	MouseClickCalc( $posClick[0], $posClick[1], 1, 0 )
	Sleep( 10 )
WEnd

; timed check method
Func TimedCheck()
	; check for boss level
	If $bossRetryTimer == False Then ; only if retry timer is not running
		If Not $isBossLevel Then
			If CheckBossLevel() Then
				Debug("detected boss level")
				; set boss level flags
				$isBossLevel = True

				; init level timer if not running
				If $bossLevelTimer == False Then
					Debug("initialized boss level timer")
					$bossLevelTimer = TimerInit()
					$bossLevelCheckTimer = TimerInit()
				EndIf
				ActivateSpells()
			Else
				$isBossLevel = False
			EndIf
		Else
			CheckBossLevelFail()
		EndIf
	Else
		; check and maybe reset retry timer
		If TimerDiff ( $bossRetryTimer ) > $timeBossRetryInterval Then
			Debug("reset boss retry timer")
			$bossRetryTimer = False ; reset timer
			$hasBossLevel = False ; allow level switching
		EndIf
	EndIf

	; check for next level
	If Not $hasBossLevel And ( CheckHasNextLevel() Or CheckNewNextLevel() ) Then
		Debug("detected new level")
		GotoNextLevel()
	EndIf
EndFunc

Func CheckBossLevel()
	If PixelSearchPos( $posBossCheck[0], $posBossCheck[1], $colorBossCheck, 5 ) <> False Then
		Return True
	EndIf
	Return False
EndFunc

Func ActivateSpells()
	Send($spellActivationOrder)
EndFunc

Func CheckBossLevelFail()
	$diff = TimerDiff( $bossLevelCheckTimer )
	If $diff > $timeBossCheckInterval Then
		Debug("checking boss level for possible failure (check interval)")
		; check color of health bar. if the bar is still green, abort boss level as it is about to fail
		If PixelSearchPos( $posHealthCheck[0], $posHealthCheck[1], $colorHealthCheckFull, 16 ) <> False Or PixelSearchPos( $posHealthCheck[0], $posHealthCheck[1], $colorHealthCheckQuarter, 16 ) <> False Then
			Debug("detected boss level will fail; timer: " & $diff)
			BossLevelFailed()
		EndIf
		$bossLevelCheckTimer = TimerInit()
	EndIf
	$diff = TimerDiff( $bossLevelTimer )
	If $diff > $timeBossLevelTimer Then
		Debug("checking boss level for possible failure (boss level timer is up)")
		If CheckBossLevel() Then
			; when the level timer is up and we are still in a boss level, assume it has failed
			Debug("assuming boss level has failed; timer: " & $diff)
			BossLevelFailed()
		EndIf
	EndIf
EndFunc

Func BossLevelFailed()
	Debug("setting boss level as status FAILED")
	; reset boss flags
	$bossLevelTimer = False
	$bossLevelCheckTimer = False
	$isBossLevel = False
	; start retry timer
	Debug("initialized boss retry timer")
	$bossRetryTimer = TimerInit()
	; set has boss level flag
	$hasBossLevel = True
	$mayDetectDead = False
	; go to previous level
	GotoPreviousLevel()
EndFunc


Func DoLevelUps()
	; scroll to bottom
	ScrollToBottom()
	; init variables
	$maxLevelUpTimeTimer = TimerInit()
	$scrollCounter = 0
	; while there are possible level ups stay in the loop
	While True
		; at max only level up for a specified amount of time
		If TimerDiff( $maxLevelUpTimeTimer ) > $timeLevelUpMax Then
			ExitLoop
		EndIf

		$colorCoord = PixelSearch( CalcX($rectLevelUp[0]), CalcY($rectLevelUp[1]), CalcX($rectLevelUp[2]), CalcY($rectLevelUp[3]), $colorLevelUp, 5, 1, $hwnd )
		If Not @error Then
			; click level up button
			MouseClick( $MOUSE_CLICK_PRIMARY, $colorCoord[0], $colorCoord[1], 1, 0 )
			; reset scroll counter
			$scrollCounter = 0
		Else
			; click scrollbar up button
			MouseClickCalc( $posScrollbarButtonUp[0], $posScrollbarButtonUp[1], 1, 0 )
			$scrollCounter = $scrollCounter + 1
			If $scrollCounter > $countScrollRetries Then
				ExitLoop
			EndIf
		EndIf
		Sleep ( 10 )
	WEnd
EndFunc

Func CheckForFish()
	Debug("searching fish leaf")
	$leafCoords = PixelSearch( $winPos[0], $winPos[1], $winPos[0]+$winPos[2], $winPos[1]+$winPos[3], $colorFishLeaf, 5, 1, $hwnd )
	If Not @error Then
		Debug("found leaf ("&$leafCoords[0]&","&$leafCoords[1]&"), searching stick")
		$stickCoords = PixelSearch( $leafCoords[0] - 10, $leafCoords[1] - 30, $leafCoords[0] + 35, $leafCoords[1] + 35, $colorFishStick, 15, 1, $hwnd )
		If Not @error Then
			Debug("found stick ("&$stickCoords[0]&","&$stickCoords[1]&"), searching mouth")
			$mouthCoords = PixelSearch( $stickCoords[0] , $stickCoords[1] , $stickCoords[0] + 60, $stickCoords[1] + 60, $colorFishMouth, 15, 1, $hwnd )
			If Not @error Then
				Debug("found mouth ("&$mouthCoords[0]&","&$mouthCoords[1]&"), FOUND FISH!")
				MouseClick( $MOUSE_CLICK_PRIMARY, $mouthCoords[0], $mouthCoords[1], 1, 0 )
				Return
			EndIf
		EndIf
	EndIf
	Debug("fish not found")
EndFunc

Func CheckHealthFull()
	Return PixelSearchPos( $posHealthCheck[0], $posHealthCheck[1], $colorHealthCheckFull, 16 ) <> False
EndFunc

Func CheckHealthDead()
	Return PixelSearchPos( $posHealthCheck[0], $posHealthCheck[1], $colorHealthCheckBarEmpty, 16 ) <> False
EndFunc


; level switching methods

Func GotoNextLevel()
	; only switch if not blocked by failed boss level
	If Not $hasBossLevel Then
		Debug("going to new level")
		MouseClickCalc( $posCheckNextLevel[0], $posCheckNextLevel[1], 1, 0 )
		; reset flags, timers and other vars
		$isBossLevel = False
		$hasBossLevel = False
		$bossLevelTimer = False
		$bossLevelCheckTimer = False
		$bossRetryTimer = False
		$fullHealthTimer = False
		$mayDetectDead = False
		$timeRequired = $timeRequiredReset
	EndIf
EndFunc

Func GotoPreviousLevel()
	MouseClickCalc( $posPreviousLevel[0], $posPreviousLevel[1], 1, 0 )
EndFunc

Func ScrollToBottom()
	; check if scrollbar is at bottom
	While PixelSearchPos( $posScrollbarCheck[0], $posScrollbarCheck[1], $colorScrollbarBar, 5 ) == False
		MouseClickCalc( $posScrollbarCheck[0], $posScrollbarCheck[1], 1, 0) ; move scrollbar to bottom
	WEnd
EndFunc








; == helper methods ==
; calculate x position based on window size and pos
Func CalcX ($x)
	Return Round( ( $x / $winSizeDefault[0] ) * $winPos[2] ) + $winPos[0]
EndFunc

; calculate y position based on window size and pos
Func CalcY ($y)
	Return Round( ( $y / $winSizeDefault[1] ) * $winPos[3] ) + $winPos[1]
EndFunc

; search a specific color at a position
Func PixelSearchPos($x, $y, $color, $var)
	$x = CalcX($x)
	$y = CalcY($y)
	$colorCoord = PixelSearch( $x-2, $y-2, $x+2, $y+2, $color, $var, 1, $hwnd )
	If Not @error Then
		Return $colorCoord
	EndIf

	Return False
EndFunc

Func MouseClickCalc($x, $y, $count, $speed)
	MouseClick( $MOUSE_CLICK_PRIMARY, CalcX($x), CalcY($y), $count, $speed )
EndFunc



; == next level detection ==
Func CheckHasNextLevel()
	$colorCoord = PixelSearch( CalcX($rectHasNextLevel[0]), CalcY($rectHasNextLevel[1]), CalcX($rectHasNextLevel[2]), CalcY($rectHasNextLevel[3]), $colorHasNextLevel, $colorHasNextLevelVar, $rectHasNextLevelSkip, $hwnd )
	If Not @error Then
		Return True
	EndIf
	Return False
EndFunc

Func CheckNewNextLevel()
	$colorCoord = PixelSearch( CalcX($posCheckNextLevel[0] - 2), CalcY($posCheckNextLevel[1] - 2), CalcX($posCheckNextLevel[0] + 2), CalcY($posCheckNextLevel[1] + 2), $colorCheckNextLevel, $colorCheckNextLevelVar, 1, $hwnd )
	If Not @error Then
		MsgBox($MB_SYSTEMMODAL, "", "new next level")
		Return True
	EndIf
	Return False
EndFunc




















Func Debug($text)
	ConsoleWrite($text & @CRLF)
EndFunc


Func MessageBox ($title, $text)
	MsgBox( $MB_SYSTEMMODAL, $title, $text )
EndFunc


Func Terminate ()
	Exit
EndFunc
