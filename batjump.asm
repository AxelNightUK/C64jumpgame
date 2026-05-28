; ==============================================================================
 ; Axel AI assisted game code - High Performance Frame Rate Version (VBLANK Fixed)
 ; ==============================================================================

file_to_import = "chill.prg"

; 1. Read just the first 2 bytes (the PRG header)
prg_header = binary(file_to_import, 0, 2)

; 2. Calculate the 16-bit load address
load_address = prg_header[0] | (prg_header[1] << 8)

; 3. Set the Program Counter
* = load_address

; 4. Include the actual data
.binary file_to_import, 2

 ; --- Hardware Constants ---
 VIC_SPR0_X   = $d000
 VIC_SPR0_Y   = $d001
 VIC_SPR_MSB  = $d010
 VIC_CTRL1    = $d011
 VIC_RASTER   = $d012
 VIC_SPR_EN   = $d015
 VIC_CTRL2    = $d016
 VIC_MEM_PTR  = $d018
 VIC_SPR_COL  = $d01e
 VIC_BORDER   = $d020
 VIC_BG       = $d021
 VIC_MC1      = $d022
 VIC_MC2      = $d023
 VIC_SPR0_COL = $d027

 CIA1_PRA     = $dc00
 CIA1_PRB     = $dc01

 ; --- SID Audio Constants ---
 SID_S3_LO    = $d40e
 SID_S3_HI    = $d40f
 SID_S3_PWLO  = $d410
 SID_S3_PWHI  = $d411
 SID_S3_CTRL  = $d412
 SID_S3_AD    = $d413
 SID_S3_SR    = $d414
 SID_VOL      = $d418

 ; --- Zero Page Variables ---
 y_vel         = $02
 current_floor = $03
 temp_lsb      = $04
 temp_msb      = $05
 temp_calc_lsb = $06
 score         = $07
 frames        = $08
 seconds       = $09
 minutes       = $0a
 current_level = $0b
 y_sub_pos     = $0c
 y_sub_vel     = $0d
 screen_ptr    = $fb
 color_ptr     = $fd

 ; ==============================================================================
 ; BASIC Stub (10 SYS 2064)
 ; ==============================================================================
 *=$0801
          .byte $0c, $08, $0a, $00, $9e, $20
          .byte $32, $30, $36, $34, $00, $00, $00

 ; ==============================================================================
 ; Initialization
 ; ==============================================================================
 *=$0810
 start    sei
          jsr copy_font
          jsr load_custom_tiles

          lda #$1c
          sta VIC_MEM_PTR

          lda VIC_CTRL2
          ora #$10
          sta VIC_CTRL2

          lda #$01
          jsr $6c20        ; Init music

          lda #$00
          sta VIC_BORDER
          sta VIC_BG

          lda #$09
          sta VIC_MC1
          lda #$0d
          sta VIC_MC2

          lda #$80
          sta $07f8

          jsr reset_position_sub
          jmp title_screen

 ; ==============================================================================
 ; Game State: Title Screen
 ; ==============================================================================
 title_screen
          lda #$01
          sta current_level
          jsr load_level
          jsr draw_level
          jsr draw_title_text

          lda #$01
          sta VIC_SPR0_COL

 wait_f1_start
          jsr check_f1
          bne wait_f1_start
          jsr debounce_f1

 start_new_game
          lda #$0f
          sta VIC_SPR_EN

          lda #$82
          sta $07f9
          sta $07fa
          sta $07fb

          lda #$07
          sta $d028
          sta $d029
          sta $d02a

          lda #$50
          sta VIC_SPR0_X+2
          lda #$90
          sta VIC_SPR0_X+4
          lda #$d0
          sta VIC_SPR0_X+6

          lda #$40
          sta VIC_SPR0_Y+2
          lda #$70
          sta VIC_SPR0_Y+4
          lda #$a0
          sta VIC_SPR0_Y+6

          lda #$01
          sta current_level
          jsr load_level
          jsr draw_level

          lda #$00
          sta score
          jsr update_score_display

          lda #50
          sta frames
          lda #$00
          sta seconds
          lda #$03
          sta minutes
          jsr draw_timer

          lda #$07
          sta VIC_SPR0_COL
          jsr reset_position_sub

 ; ==============================================================================
 ; Main Game Loop
 ; ==============================================================================
 main_loop
          jsr wait_frame

 ; --- Timer Logic ---
          dec frames
          bne skip_timer

          lda #50
          sta frames

          lda seconds
          bne do_dec_sec

          lda minutes
          bne do_dec_min
          jmp time_up

 do_dec_min
          sed
          sec
          sbc #$01
          sta minutes
          cld
          lda #$59
          sta seconds
          jmp update_timer_disp

 do_dec_sec
          sed
          sec
          sbc #$01
          sta seconds
          cld

 update_timer_disp
          jsr draw_timer
 skip_timer

 ; --- Bat Updates & Collision ---
          jsr update_bats

          lda VIC_SPR_COL
          and #$01
          beq check_floor_and_grav
          jmp player_death

 ; --- Floor Update & Gravity ---
 check_floor_and_grav
          lda VIC_SPR0_X
          ldy VIC_SPR_MSB
          jsr get_height
          sta current_floor

 do_gravity
          lda y_vel
          bmi is_jumping
          cmp #$06
          bcs apply_y
          bcc apply_grav

 is_jumping
          lda y_vel
          clc
          adc #$20
          sta SID_S3_HI

 apply_grav
          lda y_sub_vel
          clc
          adc #$80
          sta y_sub_vel

          lda y_vel
          adc #$00
          sta y_vel

 apply_y
          lda y_sub_pos
          clc
          adc y_sub_vel
          sta y_sub_pos

          lda VIC_SPR0_Y
          adc y_vel
          sta VIC_SPR0_Y

 check_floor
          cmp current_floor
          bcc check_roof

          lda current_floor
          cmp #$dd
          bcs let_it_fall

          sta VIC_SPR0_Y
          lda #$00
          sta y_vel
          sta y_sub_vel
          sta y_sub_pos
          jmp check_w

 let_it_fall
          lda VIC_SPR0_Y
          cmp #$dd
          bcc continue_fall
          jmp player_death
 continue_fall
          jmp check_w

 check_roof
          lda VIC_SPR0_Y
          cmp #$32
          bcs check_w
          lda #$32
          sta VIC_SPR0_Y
          lda #$00
          sta y_vel
          sta y_sub_vel

 ; --- Input Handling ---
 check_w
          lda #$80
          ldx VIC_SPR0_Y
          cpx current_floor
          beq update_anim
          lda #$81
 update_anim
          sta $07f8

          lda #$fd
          sta CIA1_PRA
          nop
          nop
          lda CIA1_PRB
          and #$02
          bne check_a

          lda VIC_SPR0_Y
          cmp current_floor
          bne check_a

          ; Initiating Jump
          lda #$f8
          sta y_vel
          lda #$00
          sta y_sub_vel
          sta y_sub_pos

          ; Jump Sound (Voice 3 Only)
          lda #$09
          sta SID_S3_AD
          lda #$00
          sta SID_S3_SR
          sta SID_S3_PWLO
          lda #$08
          sta SID_S3_PWHI
          lda #$00
          sta SID_S3_LO
          lda #$40
          sta SID_S3_CTRL
          lda #$41
          sta SID_S3_CTRL

 check_a
          lda CIA1_PRB
          and #$04
          bne check_d

          lda VIC_SPR_MSB
          and #$01
          bne check_a_collide

          lda VIC_SPR0_X
          cmp #$18
          bcc check_d
          beq check_d

 check_a_collide
          lda VIC_SPR0_X
          sec
          sbc #1
          sta temp_calc_lsb
          lda VIC_SPR_MSB
          and #$01
          sbc #0
          tay
          lda temp_calc_lsb
          jsr get_height

          cmp VIC_SPR0_Y
          bcc check_d

          lda VIC_SPR0_X
          bne do_dec_a
          lda VIC_SPR_MSB
          and #$fe
          sta VIC_SPR_MSB
 do_dec_a
          dec VIC_SPR0_X

 check_d
          lda #$fb
          sta CIA1_PRA
          nop
          nop
          lda CIA1_PRB
          and #$04
          bne end_input

          lda VIC_SPR_MSB
          and #$01
          beq check_d_collide
          lda VIC_SPR0_X
          cmp #$3f
          bcs score_and_reset

 check_d_collide
          lda VIC_SPR0_X
          clc
          adc #1
          sta temp_calc_lsb
          lda VIC_SPR_MSB
          and #$01
          adc #0
          tay
          lda temp_calc_lsb
          jsr get_height

          cmp VIC_SPR0_Y
          bcc end_input

          inc VIC_SPR0_X
          bne end_input
          lda VIC_SPR_MSB
          ora #$01
          sta VIC_SPR_MSB

 end_input
          lda #$ff
          sta CIA1_PRA
          jmp main_loop

 ; ==============================================================================
 ; Score & Reset Logic
 ; ==============================================================================
 score_and_reset
          sed
          clc
          lda score
          adc #$01
          sta score
          cld

          inc current_level
          lda current_level
          cmp #$03
          bcc setup_next_level
          lda #$01
          sta current_level

 setup_next_level
          jsr load_level
          jsr draw_level

          jsr update_score_display
          jsr draw_timer

          ; Level Complete Sound (Voice 3 Only)
          lda #$09
          sta SID_S3_AD
          lda #$00
          sta SID_S3_SR
          sta SID_S3_LO
          lda #$50
          sta SID_S3_HI
          lda #$10
          sta SID_S3_CTRL
          lda #$11
          sta SID_S3_CTRL

          ldx #15
 ting_wait_loop
          jsr wait_frame
          dex
          bne ting_wait_loop

          lda #$10
          sta SID_S3_CTRL

 reset_position
          jsr reset_position_sub
          jmp end_input

 reset_position_sub
          lda #$18
          sta VIC_SPR0_X
          lda #$E5
          sta VIC_SPR0_Y

          lda VIC_SPR_MSB
          and #$fe
          sta VIC_SPR_MSB

          lda #$00
          sta y_vel
          sta y_sub_vel
          sta y_sub_pos
          rts

 ; ==============================================================================
 ; Drawing Subroutines
 ; ==============================================================================
 draw_level
          lda #$20
          ldx #$00
 clear_loop
          sta $0400,x
          sta $0500,x
          sta $0600,x
          sta $06e8,x
          inx
          bne clear_loop

          lda #$01
          ldx #$00
 color_loop
          sta $d800,x
          sta $d900,x
          sta $da00,x
          sta $db00,x
          inx
          bne color_loop

          ldx #$00
 draw_col
          lda floor_heights,x
          sec
          sbc #50
          lsr
          lsr
          lsr
          tay

          lda row_lo,y
          sta screen_ptr
          sta color_ptr

          lda row_hi,y
          sta screen_ptr+1

          clc
          adc #$d4
          sta color_ptr+1

          txa
          tay

          lda #$0d
          sta (color_ptr),y
          lda #$a0
          sta (screen_ptr),y

 draw_down
          clc
          lda screen_ptr
          adc #40
          sta screen_ptr
          lda color_ptr
          adc #40
          sta color_ptr
          bcc skip_hi
          inc screen_ptr+1
          inc color_ptr+1
 skip_hi

          lda screen_ptr+1
          cmp #$07
          bcc do_draw_dirt
          bne next_col
          lda screen_ptr
          cmp #$e8
          bcs next_col

 do_draw_dirt
          lda #$0d
          sta (color_ptr),y
          lda #$a1
          sta (screen_ptr),y
          jmp draw_down

 next_col
          inx
          cpx #40
          bcc draw_col

          lda #$02
          ldy #$a2
          ldx #$00
 bottom_red_loop
          sta $dbc0,x
          tya
          sta $07c0,x
          inx
          cpx #40
          bne bottom_red_loop

          rts

 ; ==============================================================================
 ; Bat Update
 ; ==============================================================================
 update_bats
          ldx #$00
          ldy #$00
 ub_loop
          lda VIC_SPR0_Y+2,x
          clc
          adc bat_dirs,y
          sta VIC_SPR0_Y+2,x

          cmp #$30
          bcc ub_reverse
          cmp #$c0
          bcs ub_reverse
          jmp ub_next
 ub_reverse
          lda bat_dirs,y
          eor #$fe
          sta bat_dirs,y
 ub_next
          inx
          inx
          iny
          cpy #$03
          bne ub_loop
          rts

 bat_dirs .byte $01, $ff, $01

 ; ==============================================================================
 ; Initialization & Data Loading Routines
 ; ==============================================================================
 copy_font
          sei
          lda $01
          and #$fb
          sta $01

          ldx #$00
 cf_loop
          lda $d000,x
          sta $3000,x
          lda $d100,x
          sta $3100,x
          lda $d200,x
          sta $3200,x
          lda $d300,x
          sta $3300,x
          inx
          bne cf_loop

          lda $01
          ora #$04
          sta $01
          cli
          rts

 load_custom_tiles
          ldx #$00
 lt_loop
          lda grass_tile_data,x
          sta $3500,x
          lda dirt_tile_data,x
          sta $3508,x
          lda lava_tile_data,x
          sta $3510,x
          inx
          cpx #$08
          bne lt_loop
          rts

 grass_tile_data
          .byte %11111111, %10111011, %01101101, %01010101
          .byte %00010001, %01010101, %01000101, %01010101

 dirt_tile_data
          .byte %01010101, %00010001, %01010101, %01010101
          .byte %01000101, %01010101, %01010101, %01010101

 lava_tile_data
          .byte %11111111, %11100111, %10011001, %01111110
          .byte %11111111, %11100111, %10011001, %01111110

 load_level
          lda current_level
          cmp #$02
          beq load_l2
 load_l1  ldx #39
 ll1_loop lda level_1_data,x
          sta floor_heights,x
          dex
          bpl ll1_loop
          rts
 load_l2  ldx #39
 ll2_loop lda level_2_data,x
          sta floor_heights,x
          dex
          bpl ll2_loop
          rts

 time_up
          lda #$02
          sta VIC_SPR0_COL
          jsr draw_title_text
 wait_f1_restart
          jsr check_f1
          bne wait_f1_restart
          jsr debounce_f1
          jmp start_new_game

 check_f1
          lda #$fe
          sta CIA1_PRA
          lda CIA1_PRB
          and #$10
          rts

 debounce_f1
 db_loop  jsr check_f1
          beq db_loop
          rts

 player_death
          lda #$02
          sta VIC_SPR0_COL

          ; Death Sound (Voice 3 Only)
          lda #$00
          sta SID_S3_AD
          lda #$f0
          sta SID_S3_SR
          lda #$20
          sta SID_S3_LO
          lda #$05
          sta SID_S3_HI
          lda #$20
          sta SID_S3_CTRL
          lda #$21
          sta SID_S3_CTRL

          ldx #50
 death_wait_loop
          jsr wait_frame
          dex
          bne death_wait_loop

          lda #$20
          sta SID_S3_CTRL
          lda #$07
          sta VIC_SPR0_COL
          jmp reset_position

 ; ==============================================================================
 ; Optimized Core Subroutines
 ; ==============================================================================
 wait_frame
          ; 1. Wait until we are out of the Vertical Blank (lines 0-255)
 wf_1     lda VIC_CTRL1
          bmi wf_1          ; Loop if bit 7 is 1

          ; 2. Wait until we ENTER the Vertical Blank (line 256)
 wf_2     lda VIC_CTRL1
          bpl wf_2          ; Loop if bit 7 is 0

          ; 3. Safely execute music logic in the unseen area of the screen
          txa
          pha
          tya
          pha
          jsr $6c40         ; Play music
          pla
          tay
          pla
          tax
          rts

 update_score_display
          lda score
          lsr
          lsr
          lsr
          lsr
          ora #$30
          sta $0400
          lda score
          and #$0f
          ora #$30
          sta $0401
          rts

 draw_timer
          lda minutes
          ora #$30
          sta $0423
          lda #$3a
          sta $0424
          lda seconds
          lsr
          lsr
          lsr
          lsr
          ora #$30
          sta $0425
          lda seconds
          and #$0f
          ora #$30
          sta $0426
          rts

 draw_title_text
          ldx #$00
 title_loop
          lda txt_press_f1,x
          cmp #$ff
          beq title_done
          sta $05eb,x
          inx
          bne title_loop
 title_done
          rts

 get_height
          cpy #$01
          beq gh_msb_set

 gh_msb_clear
          sec
          sbc #12
          bcc gh_oob_left
          lsr
          lsr
          lsr
          tax
          jmp gh_safe_read

 gh_msb_set
          sec
          sbc #12
          bcs gh_msb_normal
          lsr
          lsr
          lsr
          tax
          jmp gh_cap_check

 gh_msb_normal
          lsr
          lsr
          lsr
          clc
          adc #32
          tax
          jmp gh_cap_check

 gh_cap_check
          cpx #40
          bcc gh_safe_read
          ldx #39
          bne gh_safe_read

 gh_oob_left
          ldx #0

 gh_safe_read
          lda floor_heights,x
          sec
          sbc #24
          rts

 ; ==============================================================================
 ; Fixed Data & Arrays
 ; ==============================================================================
 *=$1000

 row_lo   .byte $00, $28, $50, $78, $a0, $c8, $f0, $18, $40, $68, $90
          .byte $b8, $e0, $08, $30, $58, $80, $a8, $d0, $f8, $20, $48, $70, $98, $c0

 row_hi   .byte $04, $04, $04, $04, $04, $04, $04, $05, $05, $05, $05
          .byte $05, $05, $06, $06, $06, $06, $06, $06, $06, $07, $07, $07, $07, $07

 level_1_data
          .byte 229,229,245,229,245,245,229,229,229,229
          .byte 245,229,213,213,229,245,229,213,245,245
          .byte 229,229,213,213,245,245,245,213,229,229
          .byte 229,229,229,245,245,229,245,229,229,229

 level_2_data
          .byte 229,229,245,245,213,213,245,245,245,213
          .byte 213,245,245,229,229,245,245,245,229,245
          .byte 245,213,213,245,245,229,245,245,213,213
          .byte 245,245,245,229,229,245,245,213,213,229

 floor_heights
          .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
          .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

 txt_press_f1
          .byte 16, 18, 5, 19, 19, 32, 6, 49, 32, 20, 15, 32, 19, 20, 1, 18, 20, $ff

 ; ==============================================================================
 ; Sprite Graphics
 ; ==============================================================================
 *=$2000
          ; Frame 1
          .byte $00,$00,$00,$00,$00,$00,$00,$18
          .byte $00,$00,$3c,$00,$01,$ff,$80,$00
          .byte $ff,$00,$01,$ff,$80,$07,$ff,$e0
          .byte $00,$1a,$00,$00,$1c,$00,$00,$38
          .byte $00,$00,$58,$00,$00,$58,$00,$00
          .byte $3c,$00,$00,$1a,$00,$00,$1a,$00
          .byte $00,$1c,$00,$00,$38,$00,$00,$7e
          .byte $00,$00,$3c,$00,$00,$18,$00,$00

 *=$2040
          ; Frame 2
          .byte $00,$00,$00,$00,$00,$00,$00,$18
          .byte $00,$01,$bc,$80,$03,$ff,$c0,$00
          .byte $ff,$00,$01,$ff,$80,$07,$ff,$e0
          .byte $00,$1a,$00,$00,$1c,$00,$00,$38
          .byte $00,$00,$58,$00,$00,$58,$00,$00
          .byte $3c,$00,$00,$1a,$00,$00,$1a,$00
          .byte $00,$66,$00,$00,$c3,$00,$01,$81
          .byte $80,$00,$00,$00,$00,$00,$00,$00

 *=$2080
          ; Bat Sprite Graphics
          .byte $00,$00,$00,$02,$00,$40,$06,$00
          .byte $60,$0e,$18,$70,$1f,$ff,$f8,$0e
          .byte $7e,$70,$04,$3c,$20,$00,$18,$00
          .byte $00,$00,$00,$00,$00,$00,$00,$00
          .byte $00,$00,$00,$00,$00,$00,$00,$00
          .byte $00,$00,$00,$00,$00,$00,$00,$00
          .byte $00,$00,$00,$00,$00,$00,$00,$00
          .byte $00,$00,$00,$00,$00,$00,$00,$00
