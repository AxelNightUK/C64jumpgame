; ==============================================================================
 ; Axel AI assisted game code - Optimized Version (Final)
 ; ==============================================================================

 ; --- Hardware Constants ---
 VIC_SPR0_X   = $d000      ; Sprite 0 X-coordinate
 VIC_SPR0_Y   = $d001      ; Sprite 0 Y-coordinate
 VIC_SPR_MSB  = $d010      ; Most Significant Bit for Sprite X coordinates
 VIC_CTRL1    = $d011      ; VIC-II Control Register 1 (Raster MSB, screen enable)
 VIC_RASTER   = $d012      ; Current Raster Line (LSB)
 VIC_SPR_EN   = $d015      ; Sprite Enable Register
 VIC_BORDER   = $d020      ; Border Color Register
 VIC_BG       = $d021      ; Background Color Register
 VIC_SPR0_COL = $d027      ; Sprite 0 Color Register

 CIA1_PRA     = $dc00      ; CIA 1 Port A (Keyboard Matrix Row)
 CIA1_PRB     = $dc01      ; CIA 1 Port B (Keyboard Matrix Column)

 ; --- SID Chip Audio Constants ---
 SID_S1_LO    = $d400      ; Voice 1 Frequency LSB
 SID_S1_HI    = $d401      ; Voice 1 Frequency MSB
 SID_S1_PWLO  = $d402      ; Voice 1 Pulse Width LSB
 SID_S1_PWHI  = $d403      ; Voice 1 Pulse Width MSB
 SID_S1_CTRL  = $d404      ; Voice 1 Control Register (Waveform, Gate)
 SID_S1_AD    = $d405      ; Voice 1 Attack/Decay
 SID_S1_SR    = $d406      ; Voice 1 Sustain/Release
 SID_VOL      = $d418      ; SID Main Volume & Filter Configuration

 ; --- Zero Page Variables ---
 y_vel         = $02       ; Player vertical velocity
 current_floor = $03       ; Height of the floor currently beneath the player
 temp_lsb      = $04       ; Temporary variable for calculations (LSB)
 temp_msb      = $05       ; Temporary variable for calculations (MSB)
 temp_calc_lsb = $06       ; Secondary temporary variable
 score         = $07       ; BCD Score counter
 frames        = $08       ; Frame counter (counts down from 50 to 0)
 seconds       = $09       ; Seconds counter (BCD, 59 to 00)
 minutes       = $0a       ; Minutes counter (BCD, 03 to 00)
 screen_ptr    = $fb       ; 16-bit Screen RAM pointer ($FB and $FC)

 ; ==============================================================================
 ; BASIC Stub (Compiles to "10 SYS 2064")
 ; ==============================================================================
 *=$0801
          .byte $0c, $08, $0a, $00, $9e, $20
          .byte $32, $30, $36, $34, $00, $00, $00

 ; ==============================================================================
 ; Initialization
 ; ==============================================================================
 *=$0810
 start    sei              ; Disable maskable interrupts during critical setup

          lda #$00         ; Load black color code (0)
          sta VIC_BORDER   ; Set border color to black
          sta VIC_BG       ; Set background color to black

          ; Set up Sprite 0
          lda #$80         ; Value 128 (points to memory block $2000: 128 * 64)
          sta $07f8        ; Store at Sprite 0 pointer location (end of screen RAM)

          jsr reset_position_sub ; Initialize sprite to starting coordinates safely

          jmp title_screen ; Proceed to the title/wait state

 ; ==============================================================================
 ; Game State: Waiting for F1
 ; ==============================================================================
 title_screen
          jsr draw_level       ; Draw the background level
          jsr draw_title_text  ; Draw "PRESS F1 TO START" text

          lda #$01             ; Load white color code (1)
          sta VIC_SPR0_COL     ; Turn sprite white to indicate standby mode

 wait_f1_start
          jsr check_f1         ; Check if F1 is pressed
          bne wait_f1_start    ; If not pressed (Zero flag not set), loop back
          jsr debounce_f1      ; Wait for the player to release the F1 key

          lda #$01         ; Set bit 0 high
          sta VIC_SPR_EN   ; Enable Sprite 0

 start_new_game
          jsr draw_level       ; Redraw level to effectively clear the title text

          ; Reset Score
          lda #$00             ; Load 0
          sta score            ; Reset score variable
          jsr update_score_display ; Update score on screen

          ; Reset Timer to 3:00
          lda #50              ; 50 frames per second on PAL systems
          sta frames           ; Initialize frame counter
          lda #$00             ; Load 00
          sta seconds          ; Reset seconds (BCD)
          lda #$03             ; Load 03
          sta minutes          ; Reset minutes (BCD)
          jsr draw_timer       ; Draw timer to screen immediately

          ; Reset Player color and position
          lda #$07             ; Load yellow color code (7)
          sta VIC_SPR0_COL     ; Set sprite color back to active gameplay color
          jsr reset_position_sub ; Reset player to start coordinates

 ; ==============================================================================
 ; Main Game Loop
 ; ==============================================================================
 main_loop
          jsr wait_frame       ; Wait for raster to reach line 255 (screen refresh)

 ; --- Timer Logic (MM:SS BCD countdown) ---
          dec frames           ; Decrement frame counter
          bne skip_timer       ; If frames != 0, skip the clock update logic

          lda #50              ; Re-load 50 frames
          sta frames           ; Reset frame counter for the next second

          lda seconds          ; Check current seconds
          bne do_dec_sec       ; If seconds != 00, just decrement seconds

          lda minutes          ; If seconds == 00, check minutes
          bne do_dec_min       ; If minutes != 00, decrement minutes
          jmp time_up          ; If both are 00, the timer is up! End game.

 do_dec_min
          sed                  ; Enable BCD (Decimal) Mode for math
          sec                  ; Set carry flag before subtraction
          sbc #$01             ; Subtract 1 from minutes
          sta minutes          ; Store new minutes value
          cld                  ; Disable BCD Mode
          lda #$59             ; Load 59 seconds
          sta seconds          ; Reset seconds to 59
          jmp update_timer_disp ; Jump to screen update

 do_dec_sec
          sed                  ; Enable BCD (Decimal) Mode
          sec                  ; Set carry flag
          sbc #$01             ; Subtract 1 from seconds
          sta seconds          ; Store new seconds value
          cld                  ; Disable BCD Mode

 update_timer_disp
          jsr draw_timer       ; Redraw the timer numbers on screen
 skip_timer

 ; --- Update Current Floor Based on Array ---
          lda VIC_SPR0_X       ; Load Sprite 0 X position (LSB)
          ldy VIC_SPR_MSB      ; Load Sprite 0 X position (MSB)
          jsr get_height       ; Calculate floor height at this X coordinate
          sta current_floor    ; Store result in current_floor variable

 ; --- Gravity Physics ---
 do_gravity
          lda y_vel            ; Load vertical velocity
          bmi is_jumping       ; If negative (MSB set), sprite is moving upward
          cmp #$05             ; Compare velocity to terminal velocity (5)
          bcs apply_y          ; If velocity >= 5, branch to skip increasing it
          bcc apply_grav       ; If < 5, branch to increment gravity

 is_jumping
          ; --- Dynamic Pitch Bend (Mario Jump Effect) ---
          lda y_vel            ; Load current negative Y velocity
          clc
          adc #$20             ; Add base pitch to create ascending sweep effect
          sta SID_S1_HI        ; Write to SID Voice 1 Frequency MSB

 apply_grav
          inc y_vel            ; Increase downward velocity (gravity)

 apply_y
          lda VIC_SPR0_Y       ; Load current Sprite Y position
          clc                  ; Clear carry before addition
          adc y_vel            ; Add current Y velocity
          sta VIC_SPR0_Y       ; Store new Y position

 check_floor
          cmp current_floor    ; Compare new Y position with the floor height
          bcc check_roof       ; If Y < floor (higher on screen), check for roof hit

          ; --- Check if over a gap ---
          lda current_floor    ; Load floor height
          cmp #$dd             ; Is floor at $dd? (Lowest possible floor level)
          bcs let_it_fall      ; If >= $dd, it's a hole. Let player fall.

          sta VIC_SPR0_Y       ; Snap sprite exactly to the floor line
          lda #$00             ; Load 0
          sta y_vel            ; Stop vertical movement (velocity = 0)
          jmp check_w          ; Skip to jump input check

 let_it_fall
          lda VIC_SPR0_Y       ; Load Sprite Y position
          cmp #$dd             ; Compare with death depth ($dd)
          bcc continue_fall    ; If higher than death depth, continue falling

          jmp player_death     ; Hit the bottom, trigger death routine
 continue_fall
          jmp check_w          ; Continue to input checks

 check_roof
          lda VIC_SPR0_Y       ; Load Sprite Y position
          cmp #$32             ; Compare to top screen boundary ($32)
          bcs check_w          ; If below boundary, proceed to input checks
          lda #$32             ; Load top boundary value
          sta VIC_SPR0_Y       ; Snap sprite to boundary (prevent going off top)
          lda #$00             ; Load 0
          sta y_vel            ; Cancel upward velocity

 ; --- Input Handling: W / JUMP ---
 check_w
          lda #$fd             ; Select keyboard matrix row 1
          sta CIA1_PRA         ; Write to CIA 1 Port A
          lda CIA1_PRB         ; Read column from Port B
          and #$02             ; Mask bit 1 (W key)
          bne check_a          ; If not zero (not pressed), check A key

          lda VIC_SPR0_Y       ; Load Sprite Y position
          cmp current_floor    ; Check if sprite is exactly on the floor
          bne check_a          ; If not on floor, cannot jump. Check A key.

          lda #$f5             ; Load -11 (in two's complement) for jump velocity
          sta y_vel            ; Apply upward velocity

          ; --- Jump Sound ---
          lda #$0f             ; Value 15 (Max Volume)
          sta SID_VOL          ; Set master volume
          lda #$09             ; Value 9 (Attack 0, Decay 9)
          sta SID_S1_AD        ; Set voice 1 Attack/Decay
          lda #$00             ; Value 0
          sta SID_S1_SR        ; Set voice 1 Sustain/Release to 0
          sta SID_S1_PWLO      ; Set Pulse Width LSB to 0
          lda #$08             ; Value 8
          sta SID_S1_PWHI      ; Set Pulse Width MSB
          lda #$00             ; Value 0
          sta SID_S1_LO        ; Set frequency LSB to 0 (dynamic bend later)

          lda #$40             ; Pulse Waveform, Gate OFF
          sta SID_S1_CTRL      ; Reset envelope
          lda #$41             ; Pulse Waveform, Gate ON
          sta SID_S1_CTRL      ; Trigger sound

 ; --- Input Handling: A / LEFT ---
 check_a
          lda CIA1_PRB         ; Read CIA 1 Port B (Still on Row 1)
          and #$04             ; Mask bit 2 (A key)
          bne check_d          ; If not pressed, check D key

          lda VIC_SPR_MSB      ; Load Sprite MSB register
          and #$01             ; Check if Sprite 0 MSB is set (X > 255)
          bne check_a_collide  ; If MSB set, skip left boundary check

          lda VIC_SPR0_X       ; Load Sprite X position
          cmp #$18             ; Compare to left visual edge ($18)
          bcc check_d          ; If less than edge, don't move left
          beq check_d          ; If equal to edge, don't move left

 check_a_collide
          lda VIC_SPR0_X       ; Load Sprite X position
          sec                  ; Set carry for subtraction
          sbc #1               ; Subtract 1 to look ahead left
          sta temp_calc_lsb    ; Store look-ahead X position
          lda VIC_SPR_MSB      ; Load Sprite MSB
          and #$01             ; Isolate Sprite 0 MSB
          sbc #0               ; Subtract carry (handle MSB boundary cross)
          tay                  ; Transfer MSB to Y register
          lda temp_calc_lsb    ; Load look-ahead LSB
          jsr get_height       ; Get floor height 1 pixel to the left

          cmp VIC_SPR0_Y       ; Compare next floor height with current Y
          bcc check_d          ; If wall is higher than player, block movement

          lda VIC_SPR0_X       ; Load Sprite X
          bne do_dec_a         ; If X is not 0, branch to decrement
          lda VIC_SPR_MSB      ; If X is 0, we are crossing the 256 boundary
          and #$fe             ; Clear bit 0 (Sprite 0 MSB)
          sta VIC_SPR_MSB      ; Store updated MSB
 do_dec_a
          dec VIC_SPR0_X       ; Decrement Sprite X position

 ; --- Input Handling: D / RIGHT ---
 check_d
          lda #$fb             ; Select keyboard matrix row 2
          sta CIA1_PRA         ; Write to CIA Port A
          lda CIA1_PRB         ; Read CIA Port B
          and #$04             ; Mask bit 2 (D key)
          bne end_input        ; If not pressed, end input checks

          lda VIC_SPR_MSB      ; Load Sprite MSB register
          and #$01             ; Check if Sprite 0 MSB is set
          beq check_d_collide  ; If not set, check collision
          lda VIC_SPR0_X       ; Load Sprite X position
          cmp #$3f             ; Compare to right visual edge ($3F while MSB is 1)
          bcs score_and_reset  ; If beyond edge, player reached end! Add score.

 check_d_collide
          lda VIC_SPR0_X       ; Load Sprite X position
          clc                  ; Clear carry for addition
          adc #1               ; Add 1 to look ahead right
          sta temp_calc_lsb    ; Store look-ahead X position
          lda VIC_SPR_MSB      ; Load Sprite MSB
          and #$01             ; Isolate Sprite 0 MSB
          adc #0               ; Add carry to MSB
          tay                  ; Transfer MSB to Y register
          lda temp_calc_lsb    ; Load look-ahead LSB
          jsr get_height       ; Get floor height 1 pixel to the right

          cmp VIC_SPR0_Y       ; Compare next floor height with current Y
          bcc end_input        ; If wall is higher, block movement

          inc VIC_SPR0_X       ; Increment Sprite X position
          bne end_input        ; If X did not wrap to 0, end input
          lda VIC_SPR_MSB      ; If X wrapped to 0, cross 256 boundary
          ora #$01             ; Set bit 0 (Sprite 0 MSB)
          sta VIC_SPR_MSB      ; Store updated MSB

 end_input
          lda #$ff             ; Reset keyboard matrix
          sta CIA1_PRA         ; Write to CIA Port A
          jmp main_loop        ; Loop back to start of main game loop


 ; ==============================================================================
 ; Score & Reset Logic
 ; ==============================================================================
 score_and_reset
          sed                  ; Enable BCD Mode
          clc                  ; Clear carry for addition
          lda score            ; Load current score
          adc #$01             ; Add 1 (BCD will keep it formatted correctly)
          sta score            ; Save new score
          cld                  ; Disable BCD Mode

          jsr update_score_display ; Refresh score on screen

          ; --- High Pitch Ting Sound ---
          lda #$0f             ; Max volume
          sta SID_VOL          ; Set master volume
          lda #$09             ; Attack 0, Decay 9 (fast fade)
          sta SID_S1_AD
          lda #$00             ; Sustain 0, Release 0
          sta SID_S1_SR
          sta SID_S1_LO        ; Frequency LSB to 0
          lda #$50             ; High frequency MSB
          sta SID_S1_HI

          lda #$10             ; Triangle Wave, Gate OFF
          sta SID_S1_CTRL      ; Force SID voice reset
          lda #$11             ; Triangle Wave, Gate ON
          sta SID_S1_CTRL      ; Trigger ting sound

          ; Wait ~15 frames for ting to ring out
          ldx #15              ; Loop 15 times
 ting_wait_loop
          jsr wait_frame       ; Call extracted wait subroutine
          dex                  ; Decrement X
          bne ting_wait_loop   ; Loop until X is 0

          lda #$10             ; Gate OFF
          sta SID_S1_CTRL      ; Release envelope to silence

 reset_position
          jsr reset_position_sub ; Call subroutine to place sprite at start
          jmp end_input        ; Return to game loop

 reset_position_sub
          lda #$18             ; Default starting X (LSB)
          sta VIC_SPR0_X
          lda #$E5             ; Default starting Y
          sta VIC_SPR0_Y

          lda VIC_SPR_MSB      ; Load MSB
          and #$fe             ; Ensure bit 0 (Sprite 0 MSB) is cleared
          sta VIC_SPR_MSB

          lda #$00             ; Velocity 0
          sta y_vel
          rts                  ; Return from subroutine

 ; ==============================================================================
 ; Time Up (Game Over) State
 ; ==============================================================================
 time_up
          lda #$02             ; Load red color code (2)
          sta VIC_SPR0_COL     ; Turn player sprite red to indicate game over

          jsr draw_title_text  ; Draw "PRESS F1 TO START" text back on screen

 wait_f1_restart
          jsr check_f1         ; Poll F1 key
          bne wait_f1_restart  ; Wait until pressed
          jsr debounce_f1      ; Wait until released
          jmp start_new_game   ; Restart the game

 ; ==============================================================================
 ; Keyboard F1 Input Subroutines
 ; ==============================================================================
 check_f1
          lda #$fe             ; Select Row 0 of keyboard matrix
          sta CIA1_PRA
          lda CIA1_PRB         ; Read Columns
          and #$10             ; Check Column 4 (F1 key)
          rts                  ; Zero flag is set if PRESSED

 debounce_f1
 db_loop  jsr check_f1         ; Check F1 status
          beq db_loop          ; If Zero flag set (key held down), loop again
          rts                  ; Return once key is released

 ; ==============================================================================
 ; Player Death Routine
 ; ==============================================================================
 player_death
          ; 1. Turn sprite red
          lda #$02             ; Load red color code
          sta VIC_SPR0_COL     ; Apply to Sprite 0

          ; 2. Setup SID for low sound beep
          lda #$0f             ; Max Volume
          sta SID_VOL
          lda #$00             ; Instant Attack/Decay
          sta SID_S1_AD
          lda #$f0             ; Sustain max, Release 0
          sta SID_S1_SR
          lda #$20             ; Low frequency LSB
          sta SID_S1_LO
          lda #$05             ; Low frequency MSB
          sta SID_S1_HI

          lda #$20             ; Sawtooth Wave, Gate OFF
          sta SID_S1_CTRL      ; Reset voice
          lda #$21             ; Sawtooth Wave, Gate ON
          sta SID_S1_CTRL      ; Trigger death beep

          ; 3. Stop movement for 1 second (Wait 50 frames)
          ldx #50              ; Load 50 loop iterations
 death_wait_loop
          jsr wait_frame       ; Call extracted wait subroutine
          dex                  ; Decrement counter
          bne death_wait_loop  ; Loop until X is 0

          ; 4. Turn off sound
          lda #$20             ; Gate OFF
          sta SID_S1_CTRL      ; Silence SID

          ; 5. Restore sprite to yellow
          lda #$07             ; Load yellow color code
          sta VIC_SPR0_COL

          ; 6. Jump to reset position logic
          jmp reset_position

 ; ==============================================================================
 ; SUBROUTINE: Wait for Frame / Raster Line 255
 ; ==============================================================================
 wait_frame
 wf_1     lda VIC_CTRL1        ; Read VIC control register (contains Raster MSB)
          bmi wf_1             ; If bit 7 is set (Raster > 255), wait
 wf_2     lda VIC_RASTER       ; Read raster line LSB
          cmp #$ff             ; Compare with line 255
          bne wf_2             ; If not line 255, wait
          rts                  ; Return when bottom of screen is reached

 ; ==============================================================================
 ; SUBROUTINE: Draw Score to Top Left
 ; ==============================================================================
 update_score_display
          ; Extract the 'tens' digit
          lda score            ; Load BCD score (e.g., $15)
          lsr                  ; Shift right 4 times to isolate upper nibble
          lsr
          lsr
          lsr
          ora #$30             ; Convert to PETSCII number ($30-$39)
          sta $0400            ; Draw character at top-left screen RAM

          ; Extract the 'ones' digit
          lda score            ; Load BCD score
          and #$0f             ; Mask out upper nibble, keep lower nibble
          ora #$30             ; Convert to PETSCII number
          sta $0401            ; Draw character next to tens digit
          rts                  ; Return

 ; ==============================================================================
 ; SUBROUTINE: Draw Timer to Top Right
 ; ==============================================================================
 draw_timer
          ; Minutes
          lda minutes          ; Load BCD minutes
          ora #$30             ; Convert to PETSCII
          sta $0423            ; Draw at screen position

          ; Colon symbol
          lda #$3a             ; PETSCII for ':'
          sta $0424            ; Draw at screen position

          ; Seconds Tens
          lda seconds          ; Load BCD seconds
          lsr                  ; Shift 4 times for upper nibble
          lsr
          lsr
          lsr
          ora #$30             ; Convert to PETSCII
          sta $0425            ; Draw at screen position

          ; Seconds Ones
          lda seconds          ; Load BCD seconds
          and #$0f             ; Isolate lower nibble
          ora #$30             ; Convert to PETSCII
          sta $0426            ; Draw at screen position
          rts

 ; ==============================================================================
 ; SUBROUTINE: Draw Title Text
 ; ==============================================================================
 draw_title_text
          ldx #$00             ; Initialize X index
 title_loop
          lda txt_press_f1,x   ; Read character from text array
          cmp #$ff             ; Check for end-of-string marker ($FF)
          beq title_done       ; If $FF, we are done drawing
          sta $05eb,x          ; Write character to center of screen (Row 12)
          inx                  ; Increment index
          bne title_loop       ; Loop back for next character
 title_done
          rts                  ; Return

 txt_press_f1
          ; Screen Codes for "PRESS F1 TO START"
          .byte 16, 18, 5, 19, 19, 32, 6, 49, 32, 20, 15, 32, 19, 20, 1, 18, 20, $ff

 ; ==============================================================================
 ; SUBROUTINE: Draw Background Level
 ; ==============================================================================
 draw_level
          ; 1. Clear Screen
          lda #$20             ; Load space character ($20)
          ldx #$00             ; Initialize index
 clear_loop
          sta $0400,x          ; Clear top quarter of screen
          sta $0500,x          ; Clear second quarter
          sta $0600,x          ; Clear third quarter
          sta $06e8,x          ; Clear remainder (stops perfectly at $07E7)
                               ; * Optimized to avoid wiping $07f8 sprite pointers
          inx                  ; Increment X
          bne clear_loop       ; Loop until X wraps back to 0

          ; 2. Set color RAM to green ($05)
          lda #$05             ; Load green color code
          ldx #$00             ; Initialize index
 color_loop
          sta $d800,x          ; Set color RAM top quarter
          sta $d900,x          ; Set color RAM second quarter
          sta $da00,x          ; Set color RAM third quarter
          sta $db00,x          ; Set color RAM bottom quarter
          inx                  ; Increment X
          bne color_loop       ; Loop until X wraps to 0

          ; Overwrite the bottom row (Row 24) with Red ($02)
          lda #$02             ; Load red color code (lava/death zone)
          ldx #$00             ; Initialize index
 bottom_red_loop
          sta $dbc0,x          ; $DBC0 is the start of the 25th row in Color RAM
          inx                  ; Increment X
          cpx #40              ; Compare X to 40 (width of screen)
          bne bottom_red_loop  ; Loop until full row is red

          ; 3. Draw the vertical blocks
          ldx #$00             ; Initialize X as screen column index (0-39)
 draw_col
          lda floor_heights,x  ; Read floor height for this column
          sec                  ; Set carry
          sbc #50              ; Subtract pixel offset to align with screen rows
          lsr                  ; Divide by 8 to convert pixel Y to character Row
          lsr
          lsr
          tay                  ; Transfer row number to Y register

          lda row_lo,y         ; Get LSB of screen memory for this row
          sta screen_ptr       ; Store in zero page pointer
          lda row_hi,y         ; Get MSB of screen memory for this row
          sta screen_ptr+1     ; Store in zero page pointer

          txa                  ; Transfer column index (X) to A
          tay                  ; Transfer column index to Y

 draw_down
          lda #$a0             ; Load solid block character
          sta (screen_ptr),y   ; Write block to screen memory at (row + column)

          clc                  ; Clear carry
          lda screen_ptr       ; Load pointer LSB
          adc #40              ; Move down exactly one row (40 characters)
          sta screen_ptr       ; Store updated LSB
          bcc skip_hi          ; If no carry, skip MSB increment
          inc screen_ptr+1     ; Increment MSB if we crossed page boundary
 skip_hi

          lda screen_ptr+1     ; Load MSB
          cmp #$07             ; Are we past screen RAM MSB?
          bcc draw_down        ; If < $07 (e.g. $04, $05, $06), keep drawing down
          bne next_col         ; If > $07, stop drawing this column
          lda screen_ptr       ; If MSB is exactly $07, check LSB
          cmp #$e8             ; Are we at the end of screen RAM?
          bcc draw_down        ; If not at bottom, keep drawing

 next_col
          inx                  ; Move to next screen column
          cpx #40              ; Reached right side of screen?
          bcc draw_col         ; If not 40, loop for next column
          rts                  ; Return from drawing level

 ; ==============================================================================
 ; SUBROUTINE: Get Floor Height
 ; ==============================================================================
 get_height
          cpy #$01             ; Is MSB set? (Are we on the second screen page?)
          beq do_sub           ; If yes, branch to calculate offset
          cmp #24              ; Is X position < 24? (Left edge boundary check)
          bcs do_sub           ; If >= 24, proceed normally
          lda floor_heights    ; If < 24, force to first array value
          sec                  ; Prepare subtraction
          sbc #24              ; Offset hitbox
          rts                  ; Return
 do_sub
          sec                  ; Set carry
          sbc #12              ; Adjust X pixel to array index alignment (LSB)
          sta temp_lsb         ; Store result
          tya                  ; Bring MSB into A
          sbc #0               ; Subtract carry to adjust MSB
          sta temp_msb         ; Store adjusted MSB

          lsr temp_msb         ; Divide 16-bit X position by 8
          ror temp_lsb         ; ...to convert pixel coordinates into...
          lsr temp_msb         ; ...character grid column indices
          ror temp_lsb
          lsr temp_msb
          ror temp_lsb

          ldx temp_lsb         ; Load resulting array index
          cpx #40              ; Ensure index is not out of bounds (max 39)
          bcc safe_read        ; If < 40, read safely
          ldx #39              ; Cap index at 39
 safe_read
          lda floor_heights,x  ; Read floor height from look-up table
          sec                  ; Set carry
          sbc #24              ; Subtract hitbox height offset
          rts                  ; Return

 ; ==============================================================================
 ; Data & Lookup Tables
 ; ==============================================================================

 ; Screen RAM Row start pointers (LSB)
 row_lo   .byte $00, $28, $50, $78, $a0, $c8, $f0, $18, $40, $68, $90
          .byte $b8, $e0, $08, $30, $58, $80, $a8, $d0, $f8, $20, $48, $70, $98, $c0

 ; Screen RAM Row start pointers (MSB)
 row_hi   .byte $04, $04, $04, $04, $04, $04, $04, $05, $05, $05, $05
          .byte $05, $05, $06, $06, $06, $06, $06, $06, $06, $07, $07, $07, $07, $07

 ; Level Geography (Y pixel coordinates of the floor for each of the 40 columns)
 floor_heights
          .byte 229,229,245,229,245,245,229,229,229
          .byte 229,245,229,213,213
          .byte 229,245,229,213,245
          .byte 245,229,229,213,213,245,245,245,213,229
          .byte 229,229,229,229,245,245,229,245,229,229,229

 ; --- Sprite Data ---
 *=$2000
          .byte $00,$00,$00,$00,$00,$00,$00,$18
          .byte $00,$00,$3c,$00,$01,$ff,$80,$00
          .byte $ff,$00,$01,$ff,$80,$07,$ff,$e0
          .byte $00,$1a,$00,$00,$1c,$00,$00,$38
          .byte $00,$00,$58,$00,$00,$58,$00,$00
          .byte $3c,$00,$00,$1a,$00,$00,$1a,$00
          .byte $00,$1c,$00,$00,$38,$00,$00,$7e
          .byte $00,$00,$3c,$00,$00,$18,$00,$01
          .byte $00
