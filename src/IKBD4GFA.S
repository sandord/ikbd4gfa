;*****************************************************************************
; IKBD4GFA: IKBD routines for use in GFA basic.
; Handles keypresses and joystick state changes.
; License: Creative Commons Zero v1.0 Universal.
; Author: Sandor Drie‰nhuizen.
;*****************************************************************************

;-----------------------------------------------------------------------------
; Devpac-3 options
;-----------------------------------------------------------------------------

	opt	ATARI			; TOS executable output.
	opt	CHKPC			; Disallow non-PC addressing.
	opt	NOAUTOPC		; Disable automatic PC.
	opt	O+			; Enable all optimizations.
	opt	WARN			; Enable warning messages.

;-----------------------------------------------------------------------------
; Jump table, starts at +$1c.
;-----------------------------------------------------------------------------
	opt 	OW-			; Temporarily disable optimization warnings because the size of each jump table entry must be 2 words.

	bra	init			; +$00 = +$1c
	bra	restore			; +$04 = +$20
	bra	get_scancode_state_tbl	; +$08 = +$24
	bra	get_ascii_state_tbl	; +$0c = +$28
	bra	get_last_scancode	; +$10 = +$2c
	bra	get_joystick_states	; +$14 = +$30
	bra	interrogate_joysticks	; +$18 = +$34

	opt	OW+			; Re-enable optimization warnings.

;-----------------------------------------------------------------------------
; Constants.
;-----------------------------------------------------------------------------

IKBD_VEC		equ $118	; Keyboard interrupt vector.

IKBD_ACIA_CTRL		equ $fffffc00	; Keyboard ACIA Control register.
IKBD_ACIA_DATA		equ $fffffc02	; Keyboard ACIA Data register.

IKBD_CMD_ENABLE_MOUSE	equ $08		; Enable relative mouse position reporting (default).
IKBD_CMD_DISABLE_MOUSE	equ $12		; Disable all mouse interrupts.
IKBD_CMD_SET_JOYEVENTS	equ $14		; Set joystick event reporting mode.
IKBD_CMD_SET_JOYINTG	equ $15		; Set joystick interrogation mode.
IKBD_CMD_INTERRG_JOY	equ $16		; Interrogate joystick.

MFP_GPIP		equ $fffffa01	; MFP-ST General Purpose I/O Interrupt Port.
MFP_VECT_REG		equ $fffffa17   ; MFP-ST Vector Register.

;-----------------------------------------------------------------------------
; Initializes the IKBD.
;-----------------------------------------------------------------------------
; You must call this routine before using the remaining routines.
; This routine must be called in supervisor mode.
;-----------------------------------------------------------------------------
init:
	movem.l	d0-d2/a0-a2,-(sp)	; Save registers.

	; Initialize state. This is mandatory because the data is declared using
	; dcb.x, which means values will retain across sessions of the GFA Editor.

	lea     last_scancode(pc),a0
	clr.b	(a0)

	lea	joystick0_status(pc),a0
	clr.b   (a0)

	lea	joystick1_status(pc),a0
	clr.b   (a0)

	; Clear scancode state table.

	lea	kbd_scancode_state_tbl(pc),a0
	move.w	#128/4-1,d0

.clear_scancode_states:
	clr.l	(a0)+
	dbra.w	d0,.clear_scancode_states

	; Clear ASCII state table.

	lea	kbd_ascii_state_tbl(pc),a0
	move.w	#256/4-1,d0

.clear_ascii_states:
	clr.l	(a0)+
	dbra.w	d0,.clear_ascii_states

	bsr	disable_mouse

	; Reset all modifier keys to prevent TOS from thinking they're still
	; down after calling restore.
 
	move.w	#0,-(sp)		; Clear key states.
	move.w	#$b,-(sp)		; Kbshift().
	trap	#13
	addq.l	#4,sp			; Fix stack.	

	bsr	flush_buffer

	; Get keyboard mapping table address.

	pea	-1.w
	pea	-1.w
	pea	-1.w
	move.w	#16,-(sp)		; Keytbl.
	trap	#14			; XBIOS.
	lea	14(sp),sp		; Fix stack.

	; Store the mapping table address.

	move.l	d0,a0
	lea	kbd_map_table_addr(pc),a1
	move.l	(a0),(a1)	

	; Set end-of-interrupt mode.

	move.b	MFP_VECT_REG.w,d0	; Store old mode.
	lea	mfp_old_vect_reg(pc),a0
	move.b	d0,(a0)

	bclr	#3,MFP_VECT_REG.w	; Set mode to automatic.

	; Set the default packet handler.

	lea	determine_packet_handler(pc),a0
	lea	ikbd_packet_handler(pc),a1
	move.l	a0,(a1)

	; Store current IKBD interrupt handler.

	lea	ikbd_old_handler(pc),a0
	move.l	IKBD_VEC.w,(a0)

	; Set the new IKBD interrupt handler.

	move.w	sr,-(sp)		; Save status register.
	
	ori.w	#$700,sr		; Disable interrupts.

	lea	ikbd_main_handler(pc),a0
	move.l	a0,IKBD_VEC.w

	; Enable joystick interrogation mode.

	move.b	#IKBD_CMD_SET_JOYINTG,d0
	bsr	send_command

	move.w	(sp)+,sr		; Restore status register.
	
	movem.l	(sp)+,d0-d2/a0-a2	; Restore registers.

	rts

;-----------------------------------------------------------------------------
; Restores the IKBD.
;-----------------------------------------------------------------------------
; You must call this routine before exiting your program.
; This routine must be called in supervisor mode.
;-----------------------------------------------------------------------------
restore:
	movem.l	d0/a0,-(sp)		; Save registers.

	; Restore the old IKBD interrupt handler.

	move.w	sr,-(sp)		; Save status register.
	
	ori.w	#$700,sr		; Disable interrupts.

	lea	ikbd_old_handler(pc),a0
	move.l	(a0),IKBD_VEC.w	

	; Enable joystick event reporting mode.

	move.b	#IKBD_CMD_SET_JOYEVENTS,d0
	bsr.s	send_command

	; Restore end-of-interrupt mode.

	lea	mfp_old_vect_reg(pc),a0
	move.b	(a0),d0
	and.b	#$8,d0
	move.b	MFP_VECT_REG.w,d1
	bclr	#3,d1
	or.b	d0,d1
	move.b	d1,MFP_VECT_REG.w

	move.w	(sp)+,sr		; Restore status register.

	bsr.s	flush_buffer

	bsr	enable_mouse
	
	movem.l	(sp)+,d0/a0		; Restore registers.

	rts

;-----------------------------------------------------------------------------
; Gets the address of the scancode state table.
; The state of each key can be read from the table by using the scancode as
; the index and reading a byte where 0 means unpressed and 1 means pressed.
;-----------------------------------------------------------------------------
; Returns the address in a0.
;-----------------------------------------------------------------------------
get_scancode_state_tbl:
	lea	kbd_scancode_state_tbl(pc),a0
	
	rts

;-----------------------------------------------------------------------------
; Gets the address of the ASCII state table.
; The state of each key can be read from the table by using the ASCII code as
; the index and reading a byte where 0 means unpressed and 1 means pressed.
;-----------------------------------------------------------------------------
; Returns the address in a0.
;-----------------------------------------------------------------------------
get_ascii_state_tbl:
	lea	kbd_ascii_state_tbl(pc),a0
	
	rts

;-----------------------------------------------------------------------------
; Gets the scancode of the last pressed key.
;-----------------------------------------------------------------------------
; Returns the scancode in d0.
;-----------------------------------------------------------------------------
get_last_scancode:
	moveq.l #0,d0

	lea	last_scancode(pc),a0
	move.b	(a0),d0

	rts

;-----------------------------------------------------------------------------
; Interrogates the joysticks. The states will be available at a later time but
; the last known states can be retrieved using the get_joystick_states
; routine.
;-----------------------------------------------------------------------------
; This routine must be called in supervisor mode.
;-----------------------------------------------------------------------------
interrogate_joysticks:
	move.l	d0,-(sp)		; Save register.

	move.b	#IKBD_CMD_INTERRG_JOY,d0
	bsr.s	send_command

	move.l	(sp)+,d0		; Restore register.

	rts

;-----------------------------------------------------------------------------
; Gets the joystick states of joysticks 0 and 1.
;-----------------------------------------------------------------------------
; Returns the states in d0 with joystick 0 state in the MSB and joystick 1
; state in the LSB.
;-----------------------------------------------------------------------------
get_joystick_states:
	move.l	a0,-(sp)		; Save register.

	; Return the last known joystick state.

	moveq.l #0,d0

	lea	joystick1_status(pc),a0
	move.b	(a0),d0

	lsl.w   #8,d0

	lea	joystick0_status(pc),a0
	move.b	(a0),d0

	move.l	(sp)+,a0		; Restore register.

	rts

;-----------------------------------------------------------------------------
; Flushes the IKBD buffer.
;-----------------------------------------------------------------------------
flush_buffer:
	btst	#0,IKBD_ACIA_CTRL.w
	beq.s	.done

	move.b	IKBD_ACIA_DATA.w,d0
	bra.s	flush_buffer
.done:
	rts

;-----------------------------------------------------------------------------
; Sends a command to the IKBD.
;-----------------------------------------------------------------------------
; Parameters:
;   d0.b [command]
;-----------------------------------------------------------------------------
send_command:
.wait:
	btst  	#1,IKBD_ACIA_CTRL.w	; Is the IKBD ready to receive data?
	beq.s	.wait

	move.b	d0,IKBD_ACIA_DATA.w	; Send command.

	rts

;-----------------------------------------------------------------------------
; IKBD main interrupt handler.
;-----------------------------------------------------------------------------
; Handles IKBD interrupts.
;-----------------------------------------------------------------------------
ikbd_main_handler:
	movem.l d0-d1/a0-a1,-(sp)	; Save register(s).

.handler_loop:
	move.b	IKBD_ACIA_CTRL.w,d0	; Read command register.

	btst	#7,d0			; Interrupt request?
	beq.s	.next_packet

	btst	#0,d0			; Receiver full?
	beq.s	.no_data

	lea.l   ikbd_packet_handler(pc),a0
	move.l  (a0),a0
	jsr	(a0)			; Call the next packet handler.

	bra.s	.next_packet

.no_data:
	btst	#5,d0			; Receiver overflow?
	beq.s	.next_packet

	move.b	IKBD_ACIA_DATA.w,d0	; Flush IKBD by reading data.

.next_packet:
	btst	#4,MFP_GPIP.w		; Another interrupt to process?
	beq.s	.handler_loop

	movem.l (sp)+,d0-d1/a0-a1	; Restore register(s).

	rte

;-----------------------------------------------------------------------------
; Determines which packet handler to use for an incoming IKBD packet.
;-----------------------------------------------------------------------------
determine_packet_handler:
	moveq.w	#0,d0
	move.b	IKBD_ACIA_DATA.w,d0	; Read data.

	tst.b	d0
	beq.s	.finish

	cmp.b	#$fd,d0			; Joystick report?
	bne.s	.no_joy_packet

	; Set the next packet handler.	

	lea	ikbd_handle_joystick1_packet(pc),a0
	lea	ikbd_packet_handler(pc),a1
	move.l	a0,(a1)

	bra.s	.finish

.no_joy_packet:
	btst	#7,d0			; Keyboard break report?
	bne.s	.keyboard_break

	lea	last_scancode(pc),a0
	move.b	d0,(a0)			; Store scancode.

	move.b	#1,d1
	bsr.s	set_key_state

	bra.s	.finish

.keyboard_break:

	; Clear the last scancode.

	lea	last_scancode(pc),a0
	clr.b	(a0)

	bclr	#7,d0			; Convert to scancode.

	clr.b	d1
	bsr.s	set_key_state

.finish:
	rts

;-----------------------------------------------------------------------------
; Sets the state of a key in the scancode and ASCII state tables.
;-----------------------------------------------------------------------------
; Parameters:
;   d0.b [scancode]
;   d1.b [state] 0 (unpressed) or 1 (pressed)
;-----------------------------------------------------------------------------
set_key_state:
	and.w	#$ff,d0			; Clean excess data from register.

	; Set the state in the scancode state table.

	lea	kbd_scancode_state_tbl(pc),a0
	move.b	d1,(a0,d0.w)

	; Translate the scancode to ASCII.

	lea	kbd_map_table_addr(pc),a0
	move.l	(a0),a0
	move.b	(a0,d0.w),d0

	; Set the state in the ASCII state table.

	lea	kbd_ascii_state_tbl(pc),a0
	move.b	d1,(a0,d0.w)

	rts

;-----------------------------------------------------------------------------
; IKBD joystick 1 packet handler.
;-----------------------------------------------------------------------------
; Handles IKBD joystick 1 packet data.
;-----------------------------------------------------------------------------
ikbd_handle_joystick1_packet:

	; Set the next packet handler.

	lea	ikbd_handle_joystick0_packet(pc),a0
	lea	ikbd_packet_handler(pc),a1
	move.l	a0,(a1)

	; Store the joystick state.

	lea	joystick0_status(pc),a0
	move.b	IKBD_ACIA_DATA.w,(a0)

	rts

;-----------------------------------------------------------------------------
; IKBD joystick 0 packet handler.
;-----------------------------------------------------------------------------
; Handles IKBD joystick 0 packet data.
;-----------------------------------------------------------------------------
ikbd_handle_joystick0_packet:

	; Finalize the packet sequence by setting the default packet handler.

	lea	determine_packet_handler(pc),a0
	lea	ikbd_packet_handler(pc),a1
	move.l	a0,(a1)

	; Store the joystick state.

	lea	joystick1_status(pc),a0
	move.b	IKBD_ACIA_DATA.w,(a0)

	rts

;-----------------------------------------------------------------------------
; Disables mouse reporting from the IKBD, saving some cpu cycles.
;-----------------------------------------------------------------------------
disable_mouse:
	move.b	#IKBD_CMD_DISABLE_MOUSE,d0 ; Disable all mouse packet reporting.
	bsr	send_command

	rts

;-----------------------------------------------------------------------------
; Enables mouse reporting from the IKBD.
;-----------------------------------------------------------------------------
enable_mouse:
	move.b	#IKBD_CMD_ENABLE_MOUSE,d0 ; Enable relative mouse packet reporting.
	bsr	send_command

	rts

;-----------------------------------------------------------------------------

	even

; NOTE: These variables are not declared as a BSS section because when the
; assembled binary is inlined using the GFA Basic Editor, it is loaded as a
; raw file and BSS allocation is not applied. To avoid having to malloc/free
; the required memory space, the memory is declared in-line here.

ikbd_packet_handler:	dcb.l	1
ikbd_old_handler:	dcb.l	1

kbd_map_table_addr:	dcb.l	1
kbd_scancode_state_tbl:	dcb.b	128
kbd_ascii_state_tbl:	dcb.b	256
last_scancode:		dcb.b	1

joystick0_status:	dcb.b	1
joystick1_status:	dcb.b	1

mfp_old_vect_reg:	dcb.b	1
