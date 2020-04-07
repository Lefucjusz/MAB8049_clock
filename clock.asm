;MAB8049H, 8.867238MHz
;Simple clock and thermometer by Lefucjusz, Gdansk 2020
;Used RTC: my beloved DS12887, used temperature sensor: DS18b20 
	.cr	8048
	.tf	rom.bin,BIN
	.lf	clock.lst
	
;Defines
sec_reg	.eq $00
min_reg .eq $02
hr_reg	.eq $04
day_reg	.eq $07
mth_reg	.eq $08
yr_reg	.eq $09
a_reg	.eq $0A
b_reg	.eq $0B
c_reg	.eq $0C
d_reg	.eq $0D

skip_rom		.eq $CC
convert_t		.eq $44
read_scratchpad	.eq $BE
	
;Variables in RAM	
hr	.eq $20
min	.eq $21
sec	.eq $22
day .eq $23
mth .eq $24
yr  .eq $25
temp_int .eq $26
temp_dec .eq $27

;Fixed purpose registers
;R3 - interrupt flag
;R4 - position pointer in time set routine

;Set vectors
	.no $00 ;Set jump to main at reset vector (00h)
	jmp main
	
	.no $03 ;Set jump to external interrupt ISR at external interrupt vector (03h)
	jmp rtc_isr
	
;Main program	
main:
	mov R3,#0 ;Clear interrupt flag
	mov R4,#0 ;Clear position pointer
	mov R6,#250
	call delay_ms ;Wait for 250ms for voltages to stabilize
	call rtc_init ;Initialize DS12887 
	call lcd_init ;Initialize display
	en i ;Enable external interrupt
;Infinite loop	
loop:
	mov A,R3 
	jz loop ;Loop until flag is set
	dec R3 ;Fastest way to clear interrupt flag
	
	call blink_led
	call time_set
	call rtc_get_data
	call time_display
	call temp_get
	call temp_display
	jmp loop

;------------------Constants-------------------

;Array with number of days in month	
month_days:
	.ot ;Open table - check whether whole table and movp instruction are on the same page
	.db 31
	.db 28
	.db 31
	.db 30
	.db 31
	.db 30
	.db 31
	.db 31
	.db 30
	.db 31
	.db 30
	.db 31

;----------------Subroutines-------------------
	
;Uses R0,R1,R4
time_set:
	jt0 set_switch ;If position change button not pressed go to value setting part
	mov A,R4 ;Otherwise
	inc A
	mov R4,A ;Increment position pointer
set_switch: ;switch(position pointer)
	mov A,R4
	jz hours_set ;case 0
	
	mov A,R4
	cpl A
	inc A ;A = -A
	add A,#1 ;A = -A+1
	jz minutes_set ;case 1
	
	mov A,R4
	cpl A
	inc A ;A = -A
	add A,#2 ;A = -A+2
	jz day_set ;case 2
	
	mov A,R4
	cpl A
	inc A ;A = -A
	add A,#3 ;A = -A+3
	jz month_set ;case 3
	
	mov A,R4
	cpl A
	inc A ;A = -A
	add A,#4 ;A = -A+4
	jz year_set ;case 4
	
	jmp pos_reset ;default - reset position pointer
	
hours_set:
	jt1 set_end ;If key not pressed, leave
	mov R0,#hr 
	mov A,@R0 ;Load actual hours value
	inc A ;Increment value
	cpl A
	add A,#24 ;Compare (C = (hr < 24))
	jnc set_clear_time ;If hr >= 24 go to part setting hr = 0 and updating RTC
	cpl A
	add A,#24 ;Otherwise restore hr state before comparison
	mov @R0,A ;Store incremented value
	call rtc_set_time ;Update RTC
	jmp set_end ;Leave
minutes_set:
	jt1 set_end ;If key not pressed, return
	mov R0,#min
	mov A,@R0 ;Load actual minutes value
	inc A ;Increment value
	cpl A
	add A,#60 ;Compare (C = (min < 60))
	jnc set_clear_time ;If min >= 60 go to part setting min = 0 and updating RTC
	cpl A
	add A,#60 ;Otherwise restore min state before comparison
	mov @R0,A ;Store incremented value
	call rtc_set_time ;Update RTC
	jmp set_end ;Leave
day_set:
	jt1 set_end ;If key not pressed, return
	mov R1,#mth
	mov A,@R1
	mov R1,A ;Load actual month value
	
	mov A,#month_days ;Get address of array holding number of days in month
	add A,R1 ;Add offset to select proper month
	dec A ;Offset is counted from 0, months in RTC from 1 - compensate	
	movp A,@A ;Load number of days from array to A
	.ct ;Close month_days table after movp - if table and movp are not on the same page, assembler will raise an error
	inc A ;For easier comparison later
	mov R1,A ;Store the number in R1
	
	mov R0,#day
	mov A,@R0 ;Load actual day value	
	inc A ;Increment day
	cpl A
	add A,R1 ;Compare to number of days in that month (C = (A < month_days[mth]+1))
	jnc set_clear_date ;If day >= month_days[mth]+1 go to part setting day = 1 and updating RTC
	cpl A
	add A,R1 ;Otherwise restore min state before comparison
	mov @R0,A ;Store incremented value
	call rtc_set_date ;Update RTC
	jmp set_end ;Leave
month_set:
	jt1 set_end ;If key not pressed, return
	mov R0,#mth
	mov A,@R0 ;Load actual month value
	inc A ;Increment value
	cpl A
	add A,#13 ;Compare (C = (mth < 13))
	jnc set_clear_date ;If mth >= 13 go to part setting mth = 1 and updating RTC
	cpl A
	add A,#13 ;Otherwise restore mth state before comparison
	mov @R0,A ;Store incremented value
	call rtc_set_date ;Update RTC
	jmp set_end ;Leave
year_set:
	jt1 set_end ;If key not pressed, return
	mov R0,#yr
	mov A,@R0 ;Load actual year value
	inc A ;Increment value
	cpl A
	add A,#100 ;Compare (C = (yr < 100))
	jnc set_clear_date ;If yr >= 13 go to part setting yr = 1 and updating RTC (for simplicity I chose to start from year 2001 - project was done in 2020 anyways...)
	cpl A
	add A,#100 ;Otherwise restore mth state before comparison
	mov @R0,A ;Store incremented value
	call rtc_set_date ;Update RTC
	jmp set_end ;Leave
set_clear_time:
	mov @R0,#0 ;Load 0 to variable that was set in hours_set or minutes_set
	call rtc_set_time ;Update RTC
	jmp set_end ;Leave
set_clear_date:
	mov @R0,#1 ;Load 1 to variable that was set in day_set, month_set or year_set
	call rtc_set_date ;Update RTC
	jmp set_end ;Leave
pos_reset:
	mov R4,#0 ;Reset position pointer
set_end:
	ret

;Uses R0,R1,R2	
time_display:	
	mov R0,#0
	mov R1,#0
	call lcd_gotoxy ;Go to first line, first field
	
	mov R1,#hr	
	mov A,@R1
	mov R2,A
	call lcd_num ;Display hours
	
	mov R0,#':'
	mov R1,#1
	call lcd_write ;Display ':'
	
	mov R1,#min	
	mov A,@R1
	mov R2,A
	call lcd_num ;Display minutes
	
	mov R0,#':'
	mov R1,#1
	call lcd_write ;Display ':'
	
	mov R1,#sec	
	mov A,@R1
	mov R2,A
	call lcd_num ;Display seconds
	
	mov R0,#3
	mov R1,#1
	call lcd_gotoxy ;Go to second line, fourth field
	
	mov R1,#day	
	mov A,@R1
	mov R2,A
	call lcd_num ;Display day
	
	mov R0,#'-'
	mov R1,#1
	call lcd_write ;Display '-'
	
	mov R1,#mth	
	mov A,@R1
	mov R2,A
	call lcd_num ;Display month
	
	mov R0,#'-'
	mov R1,#1
	call lcd_write ;Display '-'
	
	mov R0,#'2'
	mov R1,#1
	call lcd_write ;Display '2'
	
	mov R0,#'0'
	mov R1,#1
	call lcd_write	;Display '0'
	
	mov R1,#yr	
	mov A,@R1
	mov R2,A
	call lcd_num ;Display year	
	ret

;Uses R0,R1,R2,R7
temp_get:
	call ow_reset ;Send bus reset condition
	mov R0,#skip_rom ;Skip ROM
	call ow_write_byte
	mov R0,#read_scratchpad ;Read scratchpad
	call ow_write_byte
	
	call ow_read_byte 
	mov A,R0
	mov R2,A ;Store received byte in R2
	call ow_read_byte
	
	call temp_convert

	call ow_reset ;Send bus reset condition
	mov R0,#skip_rom ;Skip ROM
	call ow_write_byte
	mov R0,#convert_t ;Convert temp - prepare to read next time
	call ow_write_byte
	ret	
	
;R0 - MSB, R2 - LSB, uses R0,R2
temp_convert:
	;Compute integral part
	mov A,R0 ;Load MSB
	rl A
	rl A
	rl A
	rl A ;Shift 4 times left
	anl A,#%01110000 ;Mask unneeded bits
	mov R0,A ;Store result in R0
	
	mov A,R2 ;Load LSB
	rr A
	rr A
	rr A
	rr A ;Shift 4 times right
	anl A,#%00001111 ;Mask unneeded bits
	orl A,R0 ;Add MSBs to LSBs to create result
	
	mov R0,#temp_int
	mov @R0,A ;Store computed value
	
	;Compute decimal part - ultra evil math hacking to overcome lack of division, multiplication and floats!
	;Computes 6.25*decimal_bits as (25/4)*decimal_bits, what gives 2 decimal places
	;Multiplication by 25 is done by shifting left and adding (25*x = 16*x + 8*x + x = (x << 4) + (x << 3) + x)
	;The equation has to be transformed so that the addition potentially causing overflow will be the last one, to use carry as the ninth bit of result (25*15 > 255)
	;Division by 4 is performed by right shifting, but to use carry set by addition it has to be RRC (rotate right through carry), not RR
	;So the final equation: (25/4)*x = (((x << 4) + x + (x << 3)) >>> 2; where >>> - RRC
	mov A,R2 ;Load LSB
	anl A,#%00001111 ;Get decimal bits
	mov R2,A ;Store just those bits in R2
	rl A
	rl A
	rl A
	rl A
	mov R0,A ;R0 = x << 4
	
	mov A,R2
	rl A
	rl A
	rl A ;A = x << 3
	
	add A,R2 ;First perform the addition that won't cause overflow
	add A,R0 ;Now perform the addition potentially causing overflow
	rrc A
	rrc A ;Divide by 4 with carry
	anl A,#%01111111 ;Mask MSB - result will be in 0...93 interval, so it should never be set
	mov R0,#temp_dec
	mov @R0,A ;Store computed value
	ret

;Uses R0,R1,R2	
temp_display:
	mov R0,#10
	mov R1,#0
	call lcd_gotoxy ;Go to first line, eleventh field
	
	mov R0,#temp_int
	mov A,@R0
	mov R2,A
	call lcd_num ;Display integral part
	
	mov R0,#'.'
	mov R1,#1
	call lcd_write ;Display '.'
	
	mov R0,#temp_dec
	mov A,@R0
	mov R2,A
	call lcd_num ;Display decimal part
	
	mov R0,#'C'
	mov R1,#1
	call lcd_write ;Display 'C'
	ret

;R0 - byte, R1 - cmd/data switch, uses R0,R1
lcd_write:
	anl P2,#%11011111 ;Clear RS
	;Test whether data or cmd will be sent
	mov A,R1 ;Load R1 to A to test if zero
	jz skip_rs ;Skip RS line setting - cmd will be sent
	orl P2,#%00100000 ;Set RS line - data will be sent
skip_rs:
	;Send upper nibble
	mov A,R0 ;Load byte to A
	anl A,#%11110000 ;Mask lower nibble
	outl P1,A ;Send data to P1
	
	orl P2,#%00010000 ;Set E line
	call delay_500us ;Wait for LCD	
	anl P2,#%11101111 ;Clear E line
	call delay_500us ;Wait for LCD
	
	;Send lower nibble
	mov A,R0 ;Load byte to A
	swap A ;Swap nibbles
	anl A,#%11110000 ;Mask lower nibble
	outl P1,A ;Send data to P1
	
	orl P2,#%00010000 ;Set E line
	call delay_500us ;Wait for LCD	
	anl P2,#%11101111 ;Clear E line
	call delay_500us ;Wait for LCD	
	ret
	
;R0 - y, R1 - x, uses R0,R1	
lcd_gotoxy:
	mov A,R1
	jnz second_row ;Check row
	mov A,#$80 ;If first, load address of its first position
	jmp lcd_gotoxy_write
second_row:
	mov A,#$C0 ;If second, load address of its first position
lcd_gotoxy_write:
	add A,R0 ;Add offset (y)
	mov R0,A
	mov R1,#0
	call lcd_write ;Send command
	ret

;R2 - value to be displayed, uses R0,R1,R2
lcd_num:
	mov R0,#0 ;Clear tens
	mov R1,#1 ;Chars will be sent to display
div10:
	mov A,R2 ;Load value to be displayed to A
	cpl A ;Complement value
	add A,#10 ;Add 10 (C = (R2 < 10))
	jc div10_end ;If there has been carry - break
	cpl A ;Complement A (A=R2-10)
	mov R2,A ;Store new value in R2
	inc R0 ;Increment tens
	jmp div10 ;Perform again, until R2 < 10	
div10_end:
	;Display tens
	mov A,R0
	add A,#$30 ;Add ASCII code for '0'
	mov R0,A
	call lcd_write
	
	;Display ones
	mov A,R2 
	add A,#$30 ;Add ASCII code for '0'
	mov R0,A
	call lcd_write
	ret
	
;Uses R0,R1,R6,R7	
lcd_init:
	mov R1,#0 ;Whole subroutine will be sending commands
	
	mov R0,#$30	
	call lcd_write ;Weird 4-bit init command first time...
	mov R6,#5
	call delay_ms ;Wait 5ms
	
	mov R0,#$30
	call lcd_write ;Weird repeated 4-bit init command second time...
	mov R6,#1
	call delay_ms ;Wait 1ms
	
	mov R0,#$30
	call lcd_write ;Weird repeated 4-bit init command third time...
	mov R6,#1
	call delay_ms ;Wait 1ms

	mov R0,#$02
	call lcd_write ;Init 4-bit mode
	
	mov R0,#$28
	call lcd_write ;2 lines, 5*8 matrix, 4-bit
	
	mov R0,#$0C
	call lcd_write ;Display on, cursor off
	
	mov R0,#$06
	call lcd_write ;Autoincrement cursor position, text scroll off
	
	call lcd_cls ;Clear screen
	ret
	
;Uses R0,R1,R6,R7	
lcd_cls:
	mov R1,#0
	mov R0,#$01	
	call lcd_write ;Clear display
	mov R6,#1
	call delay_ms ;Wait 1ms
	
	mov R0,#$80
	call lcd_write ;Set cursor at first place in upper row
	mov R6,#1
	call delay_ms ;Wait 1ms
	ret
	
;R0 - byte, R1 - address, uses R0,R1	
rtc_write_byte:
	;Prepare chip
	orl P2,#%00001111 ;Set DS, RNW, AS, CS high, leave other pins
	anl P2,#%11110111 ;CS to zero - enable chip	
	
	;Set address
	mov A,R1 ;Write address to port
	outl P1,A
	anl P2,#%11110011 ;Latch address (AS low)
	
	;Write data
	mov A,R0 ;Send data to port
	outl P1,A
	anl P2,#%11110001 ;Write data (RNW low)
	orl P2,#%00001111 ;DS, AS, RNW, CS high - chip disabled
	ret
	
;R0 - result, R1 - address, uses R0,R1
rtc_read_byte:
	;Prepare chip
	orl P2,#%00001111 ;Set DS, RNW, AS, CS high, leave other pins
	anl P2,#%11110111 ;CS to zero - enable chip	
	
	;Set address
	mov A,R1 ;Write address to port
	outl P1,A
	anl P2,#%11110011 ;Latch address (AS low)
	
	;Read data
	mov A,#$FF ;Set whole port to 1, so that it can be pulled down
	outl P1,A
	anl P2,#%11110010 ;Read data (DS low)
	
	in A,P1 ;Load data
	mov R0,A ;Store in R0
	orl P2,#%00001111 ;DS, AS, RNW, CS high, leave other pins - chip disabled
	ret
	
;Uses R0,R1	
rtc_init:
	mov R0,#%00101111
	mov R1,#a_reg
	call rtc_write_byte ;Enable oscillator, set periodic interrupt frequency to 2Hz
	
	mov R0,#%01000110
	mov R1,#b_reg
	call rtc_write_byte ;Enable periodic interrupt, binary data format, 24h mode
	ret

;Uses R0,R1
rtc_get_data:
	mov R1,#yr_reg
	call rtc_read_byte ;Read year
	
	mov R1,#yr
	mov A,R0
	mov @R1,A ;Store in yr variable
	
	mov R1,#mth_reg
	call rtc_read_byte ;Read month
	
	mov R1,#mth
	mov A,R0
	mov @R1,A ;Store in mth variable
	
	mov R1,#day_reg
	call rtc_read_byte ;Read day
	
	mov R1,#day
	mov A,R0
	mov @R1,A ;Store in day variable
	
	mov R1,#hr_reg
	call rtc_read_byte ;Read hour
	
	mov R1,#hr
	mov A,R0
	mov @R1,A ;Store in hr variable
	
	mov R1,#min_reg
	call rtc_read_byte ;Read minute
	
	mov R1,#min
	mov A,R0
	mov @R1,A ;Store in min variable
	
	mov R1,#sec_reg
	call rtc_read_byte ;Read second
	
	mov R1,#sec
	mov A,R0
	mov @R1,A ;Store in sec variable
	ret

;Uses R0,R1	
rtc_set_time:
	mov R0,#%10000110
	mov R1,#b_reg
	call rtc_write_byte ;Set SET bit
	
	mov R1,#hr
	mov A,@R1
	mov R0,A
	mov R1,#hr_reg
	call rtc_write_byte ;Set hours
	
	mov R1,#min
	mov A,@R1
	mov R0,A
	mov R1,#min_reg
	call rtc_write_byte ;Set minutes
	
	mov R0,#0
	mov R1,#sec_reg
	call rtc_write_byte ;Clear seconds
	
	mov R0,#%01000110
	mov R1,#b_reg
	call rtc_write_byte ;Clear SET bit, set PIE bit
	ret
	
;Uses R0,R1	
rtc_set_date:
	mov R0,#%10000110
	mov R1,#b_reg
	call rtc_write_byte ;Set SET bit

	mov R1,#yr
	mov A,@R1
	mov R0,A
	mov R1,#yr_reg
	call rtc_write_byte ;Set year
	
	mov R1,#mth
	mov A,@R1
	mov R0,A
	mov R1,#mth_reg
	call rtc_write_byte ;Set month
	
	mov R1,#day
	mov A,@R1
	mov R0,A
	mov R1,#day_reg
	call rtc_write_byte ;Set day
	
	mov R0,#%01000110
	mov R1,#b_reg
	call rtc_write_byte ;Clear SET bit, set PIE bit
	ret
	
;No registers used
ow_reset:
	anl P2,#%10111111 ;Clear OW pin
	call delay_500us ;Hold low for 500us
	orl P2,#%01000000 ;Set OW pin
	call delay_500us ;Wait for 500us for timeslot to end
	ret

;R0 - byte to be written, uses R0,R1,R7	
ow_write_byte:
	mov A,R0 ;Load byte to A
	cpl A ;Because of 8049 limitations - there's no jnbx instruction...
	mov R1,#8 ;Write 8 bits
ow_write_loop:
	mov R7,#11 ;Set delay loop counter; ~3.4us
	anl P2,#%10111111 ;Clear OW pin; ~3.4us
	jb0 ow_write_zero ;Check LSB, if not set - send zero; ~3.4us
ow_write_one:
	orl P2,#%01000000 ;Set OW pin; ~3.4us
ow_write_zero:
	nop
	djnz R7,ow_write_zero ;Wait for ~50us	
	orl P2,#%01000000 ;Set OW pin; ~3.4us
	rr A ;Shift byte one bit right; ~1.7us
	djnz R1,ow_write_loop ;Write next bit; ~3.4us
	ret

;R0 - received byte, uses R0,R1,R7
ow_read_byte:
	mov R0,#0 ;Clear result
	mov R1,#8 ;Read 8 bits
ow_read_loop:
	mov R7,#6 ;Set delay loop counter; ~3.4us
	;Shift result one bit right
	mov A,R0 ;~1.7us
	rr A ;~1.7us
	mov R0,A ;~1.7us	
	;Request read - OW pin at least 5us low
	anl P2,#%10111111 ;Clear OW pin; ~3.4us
	nop ;Wait for ~1.7us
	orl P2,#%01000000 ;Set OW pin; ~3.4us
	;Read bit and complete 60us timeslot
	in A,P2 ;Read P2; ~3.4us
	anl A,#%01000000 ;Read OW pin; ~3.4us
	jz ow_read_zero ;~3.4us
ow_read_one:
	mov A,R0 ;~1.7us
	orl A,#%10000000 ;~3.4us
	mov R0,A ;Set bit in result; ~1.7us
ow_read_zero:
	nop ;~1.7us
	djnz R7,ow_read_zero ;Wait for ~30us; ~3.4us	
	djnz R1,ow_read_loop ;Receive next bit; ~3.4us
	ret

;No registers used	
blink_led:
	in A,P2 ;Load actual P2 state
	xrl A,#%10000000 ;XOR MSB
	outl P2,A ;Write to port
	ret
	
;Uses R0,R1,R3	
rtc_isr:
	mov R1,#c_reg
	call rtc_read_byte ;Clear DS12887 PIF flag
	inc R3 ;Fastest way to set interrupt flag
	retr	
	
;~500uS delay, uses R7
delay_500us:
	mov R7,#71
delay_500us_loop:
	nop
	nop
	djnz R7,delay_500us_loop
	ret
	
;R6 - delay time in msec, uses R6,R7
delay_ms:
	mov R7,#146
delay_ms_loop:
	nop
	nop
	djnz R7,delay_ms_loop
	djnz R6,delay_ms
	ret