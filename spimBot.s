.data

# syscall constants
PRINT_STRING = 4

# movement memory-mapped I/O
VELOCITY             = 0xffff0010
ANGLE                = 0xffff0014
ANGLE_CONTROL        = 0xffff0018

# coordinates memory-mapped I/O
BOT_X                = 0xffff0020
BOT_Y                = 0xffff0024

# planet memory-mapped I/O
LANDING_REQUEST      = 0xffff0050
TAKEOFF_REQUEST      = 0xffff0054
PLANETS_REQUEST      = 0xffff0058

# puzzle memory-mapped I/O
PUZZLE_REQUEST       = 0xffff005c
SOLVE_REQUEST        = 0xffff0064

# debugging memory-mapped I/O
PRINT_INT            = 0xffff0080

# interrupt constants
DELIVERY_MASK        = 0x800
DELIVERY_ACKNOWLEDGE = 0xffff0068

# Zuniverse constants
NUM_PLANETS = 5

# planet_info struct offsets
orbital_radius = 0
planet_radius = 4
planet_x = 8
planet_y = 12
favor = 16
enemy_favor = 20
planet_info_size = 24

# puzzle node struct offsets
str = 0
solution = 8
next = 12

puzzle_ready:
	.word 0

puzzle:
	.word 8192


.text

main:
	sub	$sp, $sp, 8 #space for two variables
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw  $s7, 8($sp) #for global counter of puzzles solved
	sw 	$s6, 12($sp)

	li $s6, 0 # go to the first planet 
	li  $s7 0 # intially have solved zero puzzles
	li	$t0, DELIVERY_MASK  # put the delivery mask
	or	$t0, $t0, 1		# global interrupt enable
	mtc0	$t0, $12

puzzle_loop:
	sw	$zero, puzzle_ready # make flag zero
	la	$t0, puzzle # get the adress of puzzle
	sw	$t0, PUZZLE_REQUEST #request a puzzle

wait: # till the puzzle is ready
	lw	$t0, puzzle_ready # puzzle ready is a flag which will be changed in the interrupt handler
	beq	$t0, 0, wait

	la	$s0, puzzle #is pointing to the puzzle struct

solve_loop:
	#intial solve

	#beq $0 0 Landing

	lw	$a0, str($s0) #get the first string
	lw	$a1, str+4($s0) #get the second string 
	jal	puzzle_solve #solve the puzzle
	sw	$v0, solution($s0) #store the puzzle
	addi $s7 $s7 1 # keeps track of puzzles solve
	lw	$s0, next($s0) # go to the next puzzle
	bne	$s0, 0, solve_loop # solve until a null pointer

	#get credit for solving
	la	$t0, puzzle #give me another puzzle
	sw	$t0, SOLVE_REQUEST
	#

	#to go to another planet if solved 7 puzzles on this planet
	bgt $s7 3 Landing
	######

	j	puzzle_loop

	# never reached, but included for completeness
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	add	$sp, $sp, 8
	jr	$ra



.kdata					# interrupt handler data (separated just for readability)
chunkIH:	.space 8		# space for two registers
non_intrpt_str:	.asciiz "Non-interrupt exception\n"
unhandled_str:	.asciiz "Unhandled interrupt type\n"

.ktext 0x80000180
interrupt_handler:
.set noat
	move	$k1, $at		# Save $at                               
.set at
	la	$k0, chunkIH
	sw	$a0, 0($k0)		# Get some free registers                  
	sw	$v0, 4($k0)		# by storing them to a global variable     

	mfc0	$k0, $13		# Get Cause register                       
	srl	$a0, $k0, 2                
	and	$a0, $a0, 0xf		# ExcCode field                            
	bne	$a0, 0, non_intrpt         

interrupt_dispatch:			# Interrupt:                             
	mfc0	$k0, $13		# Get Cause register, again                 
	beq	$k0, 0, done		# handled all outstanding interrupts     

	and	$a0, $k0, DELIVERY_MASK	# is there a puzzle dwelivery interrupt?                
	bne	$a0, 0, delivery_interrupt   

	li	$v0, PRINT_STRING	# Unhandled interrupt types
	la	$a0, unhandled_str
	syscall 
	j	done

delivery_interrupt:
	sw	$zero, DELIVERY_ACKNOWLEDGE
	li	$k0, 1
	sw	$k0, puzzle_ready
	j	interrupt_dispatch

non_intrpt:				# was some non-interrupt
	li	$v0, PRINT_STRING
	la	$a0, non_intrpt_str
	syscall				# print out an error message
	# fall through to done

done:
	la	$k0, chunkIH
	lw	$a0, 0($k0)		# Restore saved registers
	lw	$v0, 4($k0)
.set noat
	move	$at, $k1		# Restore $at
.set at 
	eret


####################################
# COPY-PASTED FROM LAB 7 SOLUTIONS #
####################################

.text

puzzle_solve:
	sub	$sp, $sp, 20
	sw	$ra, 0($sp)		# save $ra and free up 4 $s registers for
	sw	$s0, 4($sp)		# str1
	sw	$s1, 8($sp)		# str2
	sw	$s2, 12($sp)		# length
	sw	$s3, 16($sp)		# i

	move	$s0, $a0		# str1
	move	$s1, $a1		# str2

	jal	my_strlen

	move 	$s2, $v0		# length
	li	$s3, 0			# i = 0
ps_loop:
	bgt	$s3, $s2, ps_return_minus_1
	move	$a0, $s0		# str1
	move	$a1, $s1		# str2
	jal	my_strcmp
	beq	$v0, $0, ps_return_i
	
	move	$a0, $s1		# str2
	jal	rotate_string_in_place_fast
	add	$s3, $s3, 1		# i ++
	j	ps_loop

ps_return_minus_1:
	li	$v0, -1
	j	ps_done

ps_return_i:
	move	$v0, $s3

ps_done:	
	lw	$ra, 0($sp)		# restore registers and return
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	add	$sp, $sp, 20
	jr	$ra

my_strcmp:
	li	$t3, 0			# i = 0
my_strcmp_loop:
	add	$t0, $a0, $t3		# &str1[i]
	lb	$t0, 0($t0)		# c1 = str1[i]
	add	$t1, $a1, $t3		# &str2[i]
	lb	$t1, 0($t1)		# c2 = str2[i]

	beq	$t0, $t1, my_strcmp_equal
	sub	$v0, $t0, $t1		# c1 - c2
	jr	$ra

my_strcmp_equal:
	bne	$t0, $0, my_strcmp_not_done
	li	$v0, 0
	jr	$ra

my_strcmp_not_done:
	add	$t3, $t3, 1		# i ++
	j	my_strcmp_loop

rotate_string_in_place_fast:
	sub	$sp, $sp, 8
	sw	$ra, 0($sp)
	sw	$a0, 4($sp)

	jal	my_strlen
	move	$t0, $v0		# length
	lw	$a0, 4($sp)
	lb	$t1, 0($a0)		# was_first = str[0]

	div	$t3, $t0, 4		# length_in_ints = length / 4;

	li	$t2, 0			# i = 0
	move	$a1, $a0		# making copy of 'str' for use in first loop
rsipf_loop1:
	bge	$t2, $t3, rsipf_loop2_prologue
	lw	$t4, 0($a1)		# unsigned first_word = str_as_array_of_ints[i]
	lw	$t5, 4($a1)		# unsigned second_word = str_as_array_of_ints[i+1]
	srl	$t6, $t4, 8		# (first_word >> 8)
	sll	$t7, $t5, 24		# (second_word << 24)
	or	$t7, $t7, $t6		# combined_word = (first_word >> 8) | (second_word << 24)
	sw	$t7, 0($a1)		# str_as_array_of_ints[i] = combined_word
	add	$t2, $t2, 1		# i ++
	add	$a1, $a1, 4		# str_as_array_of_inst ++
	j	rsipf_loop1		

rsipf_loop2_prologue:
	mul	$t2, $t3, 4
	add	$t2, $t2, 1		# i = length_in_ints*4 + 1
rsipf_loop2:
	bge	$t2, $t0, rsipf_done2
	add	$t3, $a0, $t2		# &str[i]
	lb	$t4, 0($t3)		# char c = str[i]
	sb	$t4, -1($t3)		# str[i - 1] = c
	add	$t2, $t2, 1		# i ++
	j	rsipf_loop2		
	
rsipf_done2:
	add	$t3, $a0, $t0		# &str[length]
	sb	$t1, -1($t3)		# str[length - 1] = was_first
	lw	$ra, 0($sp)
	add	$sp, $sp, 8
	jr	$ra

my_strlen:
	li	$v0, 0			# length = 0  (in $v0 'cause return val)
my_strlen_loop:
	add	$t1, $a0, $v0		# &str[length]
	lb	$t2, 0($t1)		# str[length]
	beq	$t2, $0, my_strlen_done
	
	add	$v0, $v0, 1		# length ++
	j 	my_strlen_loop

my_strlen_done:
	jr	$ra



########landing stuff
# planets array
planets:
	.space NUM_PLANETS * planet_info_size

Landing:
	# if we're on planet 0, land on planet 1,
	# otherwise land on planet - 1
	# in practice, you always start on planet 4,
	# but the handout did say "random planet" ...
	lw	$t0, LANDING_REQUEST # get planet number
	beq	$s6, 5, land_on_0 # if 5 then go to 0

	mul $t0 $s6 planet_info_size # land on the one specified by s0
	add $s6 $s6 1 # next time go to the next planet
	j	take_off

land_on_0:
	add	$t0, 0			# $t0 = offset of target planet info
	addi $s6 $0 1       #next planet to land is planet 1
take_off:
	sw	$zero, TAKEOFF_REQUEST
	li $t1 10
	sw $t1 VELOCITY

	# target destination is (150, 150 + orbital_radius)
	la	$t1, planets		# $t1 = start of planets array
	sw	$t1, PLANETS_REQUEST
	add	$t0, $t1, $t0		# $t0 = start of destination planet info

	lw	$t2, BOT_X         #get x position
	beq	$t2, 150, align_y  # 
	bgt	$t2, 150, target_left
	
	li	$t3, 0
	j	move_x

target_left:
	li	$t3, 180

move_x:
	sw	$t3, ANGLE
	li	$t3, 1
	sw	$t3, ANGLE_CONTROL

move_x_loop:
	lw	$t2, BOT_X
	bne	$t2, 150, move_x_loop

align_y:
	lw	$t2, BOT_Y
	lw	$t3, orbital_radius($t0)
	add	$t3, $t3, 150		# $t3 = target Y
	beq	$t2, $t3, wait_for_planet
	bgt	$t2, $t3, target_up
	
	li	$t4, 90
	j	move_y

target_up:
	li	$t4, 270

move_y:
	sw	$t4, ANGLE
	li	$t4, 1
	sw	$t4, ANGLE_CONTROL

move_y_loop:
	lw	$t2, BOT_Y
	bne	$t2, $t3, move_y_loop

wait_for_planet:
	sw	$zero, VELOCITY

wait_for_planet_loop:
	sw	$t1, PLANETS_REQUEST
	lw	$t2, planet_x($t0)
	bne	$t2, 150, wait_for_planet_loop
	lw	$t2, planet_y($t0)
	bne	$t2, $t3, wait_for_planet_loop

	# planet is under you; now land on it
	sw	$zero, LANDING_REQUEST

Landed:
	# jump back to solving problems
	j puzzle_loop

	# never reached, but included for completeness