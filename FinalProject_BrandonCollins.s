;Project

;----------CONSTANTS----------

;System Configuration Registers
SYSCFG	EQU 0x40013800
EXTICR1	EQU	0x08			;clock enables for GPIO ports

RCC EQU 0x40023800		;base address for RCC
APB1ENR		EQU	0x40			;APB1ENR offset	(Clock for timer)
AHB1ENR EQU 0x30 		;offset for this
GPIOA EQU 0x40020000	;base address for PA# stuff
GPIOD EQU 0x40020C00	;base address for PD# stuff
MODER EQU 0x00 			;mode selection register offset (it's 0)
IDR EQU 0x10			;input data register offset from base
ODR EQU 0x14 			;output data register offset from base
TIM4EN		EQU	0x04			;Timer 4 enable = bit 2


TIM4	EQU	0x40000800		;Timer 4 registers
CR1		EQU	0x00			;Control register 1	
DIER	EQU	0x0C			;DMA/interrupt enable register
SR		EQU	0x10			;Status register
PSC		EQU	0x28			;Prescaler (offset)
ARR		EQU	0x2C			;Auto-Reload Register
TIM4_OFF	EQU 0			;Offset to ISER0/ICER0/ISPR0/ICPR0/IABR0 (30/32 = 0) x 4

;NVIC Registers
NVIC_ISER0	EQU	0xE000E100	;Interrupt Set-Enable (0-7)
NVIC_ICER0	EQU	0xE000E180	;Interrupt Clear-Enable (0-7)
NVIC_ISPR0	EQU	0xE000E200	;Interrupt Set-Pending (0-7)
NVIC_ICPR0	EQU	0xE000E280	;Interrupt Clear-Pending (0-7)
NVIC_IABR0	EQU	0xE000E300	;Interrupt Active Bit (0-7)
NVIC_IPR1	EQU	0xE000E404	;Interrupt Priority (0-59)
STIR		EQU	0xE000EF00	;Software Tigger Interrupt
	
;External Interrupt Registers
EXTI	EQU	0x40013C00	;base address
IMR		EQU	0x00	;Interrupt Mask Register
EMR		EQU	0x04	;Event Mask Register
RTSR	EQU	0x08	;Rising Trigger Select
FTSR	EQU	0x0C	;Falling Trigger Select
SWIR	EQU	0x10	;Software Interrupt Event
PR		EQU	0x14	;Pending Register

;prescale and Auto Reload Register are discussed in class
;Hertz = cycles/second
;kHz = 1000, MHz = 1000000, GHz = 1000000000
;frequency of interrupt in Hertz = (clock frequency in Hertz)/((1+ARR)(1+PSC))
PSCVal	EQU 9999
ARRVal EQU 399
;These values will make the timer have 4 Hz, meaning it repeats every 0.25 seconds


	AREA Project, CODE
	THUMB
	ENTRY
	EXPORT __main
	EXPORT EXTI0_IRQHandler
	EXPORT TIM4_IRQHandler 		;gotta have the export for timer to work


__main PROC
	bl LEDSetup ;initialize PD12-15 (output) by calling initialization subroutine
	;turn off all lights to start (this can be in the initialization)
	bl ButtonSetup		;button intialization
	bl EXTI_init		;button PA0 to trigger EXTI0
	bl TIM4_init		;timer intialize
	cpsie	i			;enable interrupts


	;load location for output data
	ldr r11, =GPIOD
	ldr r12, [r11, #ODR]
	
	ldr r9, =ModeAandCTimer
	mov r10, #0 ;start Mode A and C Timer with 0
	strb r10, [r9]
	ldr r9, =ModeTracker
	mov r10, #0
	strb r10, [r9] ;start ModeTracker with 0
	
	;load ModCVals array
	ldr r6, =ModCVals
	
	b . ;main will loop here
	ENDP
	


;initialize all LED (PD15-12) to output, turned off
;only call this once
;modifies r0 and r1
LEDSetup	PROC
	;enable clock (read in, modify, store back)
	ldr r0, =RCC	;base address
	ldr r1, [r0, #AHB1ENR]	
	orr r1, #2_1000		;bit 3 = GPIOD (2 = GPIOC, 1 = GPIOB, 0 = GPIOA)		
	str r1, [r0, #AHB1ENR]	;put it back, now PD# clock is on
	
	;set GPIOD 15, 14, 13, 12 as outputs
	;modes: 00 input, 01 output (two bits per pin)
	;bit 31, 30 = PD15 (0,1 for output)
	;bit 29, 28 = PD14 (0,1 for output)
	;bit 27, 26 = PD13 (0,1 for output)
	;bit 25, 24 = PD12 (0,1 for output)
	; etc. ... bit 3, 2 = PD1; bit 1, 0 = PD0
	ldr r0, =GPIOD			;base address
	ldr r1, [r0, #MODER]	;read in with offset of 0 (modes)
	orr r1, #0x55000000		;2_010101010000....0000 set bits 30, 28, 26, 24
	bic r1, #0xAA000000		;2_101010100000....0000 clear 31, 29, 27, 25
	str r1, [r0, #MODER]	;store back (this is when it takes effect)

	;clear/off all four lights
	;IDR and ODR -> one bit per pin 
	;PD15 -> bit 15, etc.
	;clear bits 15, 14, 13, 12 to turn off PD15 - 12
	;blue red orange green
	ldr r1, [r0, #ODR]	;GPIOD's output data is in r1
	bic r1, #0xF000		;clear bits 15-12
	str r1, [r0, #ODR]	;stores new ODR value (PD15-12 definitely off)
	
	bx LR	;return
	ENDP

;set up PA0 as input
;modify r0 and r1
ButtonSetup	PROC
	;clock setup for GPIOA
	ldr r0, =RCC	;base address
	ldr r1, [r0, #AHB1ENR]	;current GPIO clock settings	
	orr r1, #2_0001			;setting bit 0 (0 -> GPIOA)
	str r1, [r0, #AHB1ENR]	;store it back (now GPIOA clock is going)
	
	;set PA0 mode as input (bits # 1 and 0)
	;bits to "mess with" = pin #*2 and (#*2)+1
	;01 setting for output, 00 for input
	ldr r0, =GPIOA			;base address for GPIOA stuff
	ldr r1, [r0, #MODER]	;offset of 0 to get mode settings
	bic r1, #0x03			;2_00000011 -> clears bits 1 and 0
	str r1, [r0, #MODER]	;store it, now PA0 is input

	bx LR
	ENDP



;----------TIMER AND INTERRUPT----------
	
;initialize timer 4
;frequency of interrupt in Hertz = (clock frequency in Hertz)/((1+ARR)(1+PSC))
;so 0.25 s = 4 Hz = 16000000/(1+9999)(1+399) = 16000000/(10000*400) = 16000000/4000000
TIM4_init
	;enable the clock to TIM4 
	ldr		r0,=RCC				;Clock control
	ldr		r1,[r0,#APB1ENR]	;APB1 clock enable bits
	orr		r1,#TIM4EN			;Enable TIM4 clock
	str		r1,[r0,#APB1ENR]	;Update APB1

	ldr		r0,=TIM4			;TIM4 registers
	mov		r1,#PSCVal			;Prescale for waveform generation
	str		r1,[r0,#PSC]		
	mov		r1,#ARRVal			;Auto-Repeat for waveform generation
	str		r1,[r0,#ARR]		
	ldr		r1,[r0,#CR1]		
	orr		r1, #1
	str		r1,[r0,#CR1]		;Enable the counter
	ldr		r1,[r0,#DIER]	
	orr		r1, #1
	str		r1,[r0,#DIER]		;Enable the counter interrupt
	
	; Enable TIM4 interrupt in NVIC	
	ldr		r0,=NVIC_ISER0		;NVIC_ISER0 enable registers
	ldr 	r1, [r0, #TIM4_OFF]
	orr		r1, #0x40000000		;set bit thirty
	str		r1,[r0,#TIM4_OFF]	;enable TIM4 interrupt
	bx		lr					;return
	ENDP

;----------MAIN PART OF PROJECT----------

;is "called" by the timer
TIM4_IRQHandler PROC
	push {LR}
	;reset the timer so it starts counting again
	ldr		r0,=TIM4
	ldr		r1,[r0,#SR]			;Read SR
	bic		r1,#0x0001			;Clear UIF (flag)
	str		r1,[r0,#SR]			;Update SR

;----------SELECTING MODE----------
	ldr r9, =ModeTracker
	ldrb r10, [r9]
	
	;0 means ModeA, 1 means ModeB, 2 means ModeC
	;after C, cycle back to A (would have value of 3, so start back at 0)
	cmp r10, #1
	beq ModeB
	
	cmp r10, #2
	beq ModeC
	
	b ModeA

TimerReturn
	pop {LR}
	bx LR
	
	
;----------MODE C-----------
ModeC
	ldr r3, =ModeAandCTimer
	ldrb r4, [r3]
	
	add r4, #1 ;add one to Mode C Timer count
	strb r4, [r3]
	
	cmp r4, #4 ;if 4 cycles, meaning 1 second has passed, then can continue
	beq ModeCReady

	;else
	b TimerReturn
	
ModeCReady
	;load location for output data
	ldr r11, =GPIOD
	ldr r12, [r11, #ODR]
	
	;turn off all LEDS
	and r12, #0
	str r12, [r11, #ODR]
	
	;load number in ModCVals array
	ldrb r7, [r6], #1
	cmp r7, #16
	bhs SkipNumber ;if value is higher than 15, meaning it's negative or greater than 15, then skip
	
	;shift 12 bits to the left so that they bits 3-0 of number correspond to ODR 15-12
	lsl r7, #12 
	
	;turn on corresponding LEDS
	orr r12, r7
	str r12, [r11, #ODR]	
	
	
SkipNumber
	;reset ModeC Timer
	mov r4, #0
	strb r4, [r3]
	
	;if null termination char, start array from beginning
	teq r7, #0
	bne Done

	;means null term char, so...
	;load ModCVals array from beginning
	ldr r6, =ModCVals
	
Done

	b TimerReturn
	


	
;----------MODE B-----------
ModeB
	;load location for output data
	ldr r11, =GPIOD
	ldr r12, [r11, #ODR]
	
	;add one to each LED counter
	add r4, #1 
	add r8, #1
	add r5, #1
	
	eor r12, #2_1000000000000 ;toggle Green LED, every 0.25 second which is every cycle
	
	teq r4, #2
	beq OrangeToggle ;toggle Orange LED, every 0.5 second; every two cycles
AfterOrange

	teq r8, #3
	beq RedToggle ;toggle Red LED, every 0.75 second; every 3 cycles
AfterRed

	teq r5, #4
	beq BlueToggle ;toggle Blue LED, every 1 second; every 4 cycles
AfterBlue
	
	str r12, [r11, #ODR]
	b TimerReturn
	
OrangeToggle
	;toggle orange
	eor r12, #2_10000000000000
	mov r4, #0 ;reset orange counter
	b AfterOrange

RedToggle
	;toggle red
	eor r12, #2_100000000000000
	mov r8, #0 ;reset red counter
	b AfterRed
	
BlueToggle
	;toggle blue
	eor r12, #2_1000000000000000
	mov r5, #0 ;reset blue counter
	b AfterBlue
	
	
;----------MODE A-----------
ModeA
	;load location for output data
	ldr r11, =GPIOD
	ldr r12, [r11, #ODR]
	
	ldr r3, =ModeAandCTimer
	ldrb r4, [r3]
	
	;determine which part of cycle based on Data value holding timer count
	cmp r4, #0 
	beq OrangeA
	
	cmp r4, #1
	beq RedA
	
	cmp r4, #2
	beq BlueA
	
	b GreenA

OrangeA
	;toggle PD13, Orange LED
	eor r12, #2_10000000000000
	b FinishA

RedA
	;toggle PD14, Red LED
	eor r12, #2_100000000000000
	b FinishA

BlueA
	;toggle PD15, Blue LED
	eor r12, #2_1000000000000000
	b FinishA
	
GreenA
	;toggle PD12, Green LED
	eor r12, #2_1000000000000
	b FinishA

FinishA
	str r12, [r11, #ODR] ;update LEDs
	add r4, #1 ;add one to count of the 0.25 sec cycles for Mode A
	cmp r4, #3
	bls StoreA

	mov r4, #0 ;if gone through all LEDS, go back to 0 to start cycle again
StoreA
	strb r4, [r3] ;store back the timer count for Mode A
	b TimerReturn
	
	ENDP


	
;================================================
; Interrupt on falling edge of button press on PA0 (1 to 0)
;   Triggers on EXTI0 interrupt
;   Increments global variable Pattern: 0-1-2-0-1-2....
EXTI0_IRQHandler	PROC
		push	{lr}

	;Debounce delay
		ldr		r0,=500000	;delay for switch debounce
Bounce	subs	r0,#1		;delay
		bne		Bounce		;delay

		; Verify that it was a 0-to-1 transition on PA0
		ldr		r0,=GPIOA
		ldrh	r1,[r0,#IDR] ;check button on PA0
		tst		r1,#0x01	;if 1-to-0 transition: PA0 = 0
		bne		IRQexit		;ignore bounce on 1-to-0 transition 
							;this skips next part if read a 1

;----------WHAT INTERRUPT DOES:----------
	ldr r11, =GPIOD
	ldr r12, [r11, #ODR]
	;turn off all LEDS
	and r12, #0
	str r12, [r11, #ODR]

	;reset ModeA and ModeC Timer
	ldr r5, =ModeAandCTimer
	mov r4, #0
	strb r4, [r5]

	;reset ModeB counters
	mov r5, #0 ;blue LED, PD15, every second
	mov r8, #0 ;red LED, PD14, every 0.75 second
	mov r4, #0 ;orange LED, PD13, every 0.5 second
	
	;load ModCVals array
	ldr r6, =ModCVals
	
;IMPORTANT for SWITCHING MODES
	ldr r9, =ModeTracker
	ldrb r10, [r9]
	add r10, #1	;add 1 to mode
	cmp r10, #2
	bls StoreMode
	mov r10, #0 ;cycle back around to Mode A from Mode C
StoreMode
	strb r10, [r9] ;store mode back
	
;----------------------------------------
	
	
;;;Now prep to go back from interrupt
IRQexit
    ; Reset interrupt pending bit
		ldr		r0,=EXTI	;point to EXTI register base address
		ldr		r1,[r0,#PR]	;reset EXTI0 pending bit (write 1 to it)
		orr		r1,#0x01	;bit 0 set
		str		r1,[r0,#PR]

	; Reset NVIC interrupt pending bit (in case triggered by bounce)
		ldr		r0,=NVIC_ICPR0   	;Clear interrupt-Pending Register
		orr		r1,#0x40			;EXTI0 = bit 6
		str		r1,[r0]				;Clear EXTI0 pending bit

		pop		{lr}
		bx		lr			;return from interrupt
		ENDP
;================================================
;Initialize EXTI0 interrupt via PA0 = button
EXTI_init	PROC
	;select PA0 as EXTI0
	ldr		r1,=SYSCFG
	ldrh	r2,[r1,#EXTICR1]	;EXTI priorities for EXTI0
	bic		r2,#0x0f			;Bits 3-0 = 0000 to select PA0 = EXTI0
	strh	r2,[r1,#EXTICR1]	;EXTI priorities for EXTI0

	;configure EXTI0 as falling edge triggered
	ldr		r1,=EXTI
	ldr		r2,[r1,#FTSR]		;Select falling edge trigger
	orr		r2,#1				;bit #0 for EXTI0
	str		r2,[r1,#FTSR]	

	ldr		r2,[r1,#PR]	
	orr		r2,#1				
	str		r2,[r1,#PR]			;Clear any pending event

	ldr		r2,[r1,#IMR]	
	orr		r2,#1				
	str		r2,[r1,#IMR]		;Enable EXTI0

	;configure NVIC to enable EXTI0 as priority 1
	ldr		r1,=NVIC_ISER0
	ldr		r2, [r1]
	orr		r2,#0x40			;EXTI0 is IRQ 6
	str		r2,[r1]				;Set enable IRQ 6

	ldr		r1,=NVIC_IPR1
	ldr		r2, [r1]
	orr		r2,#0x00100000		;Make EXTI0 priority 1
	str		r2,[r1]				;write IPR1 3rd byte

	bx		LR					;return
	ENDP


;values to read for Mode C
ModCVals dcb 1, -12, 12, 9, 25, 14, 0

	AREA ProjectData, DATA
ModeTracker space 1 ;used to track which mode we're in
ModeAandCTimer space 1 ;track what part of Mode A and C we're in

	END