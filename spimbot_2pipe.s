.data
# syscall constants
    PRINT_STRING = 4
    
# timer memory-mapped I/O
    TIMER                = 0xffff001c
    
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
    TIMER_MASK           = 0x8000
    TIMER_ACKNOWLEDGE    = 0xffff006c

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

# allocated memory for flags, puzzles, and planet data
    p0_ready:       .word 0             # flag values: 0 = not requested; 1 = waiting on request
    p1_ready:       .word 0             #              2 = puzzle is ready
    puzzle0:        .word 8192
    puzzle1:        .word 8192
    planets:        .space NUM_PLANETS * planet_info_size

####################################
#            MAIN PROGRAM          #
####################################
.text
main:                                   # Apply interrupt masks and global interrupt bit
    li      $t0, DELIVERY_MASK
    or      $t0, $t0, TIMER_MASK
    or      $t0, $t0, 1
    mtc0    $t0, $12                    # set status register
    li      $t0, 999950
    sw      $t0, TIMER                  # request an interrupt 50 cycles before the program ends
    
    sub     $sp, $sp, 32                # Allocate stack for saving values
    sw      $ra, 0($sp)
    sw      $s0, 4($sp)
    sw      $s1, 8($sp)
    sw      $s2, 12($sp)
    sw      $s2, 16($sp)
    sw      $s3, 20($sp)    
    sw      $s6, 24($sp)  
    sw      $s7, 28($sp)
    
    la      $s0, puzzle0
    la      $s1, puzzle1
    lw      $s6, LANDING_REQUEST        # s6 = target planet, initially set to current planet
    
pre_puzzle:                             # set up for puzzles on new planet
    move    $s7, $zero                  # initially have solved zero puzzles
    sw      $zero, p0_ready
    sw      $zero, p1_ready
solve_dispatch:                         # Pipelined puzzle request and puzzle solve queue
    li      $v0, 1                      # load constants for flagging purposes
    li      $v1, 2
    lw      $t0, p0_ready               # load the flags for p0 and p1
    lw      $t1, p1_ready
    
    bne     $t0, $zero, skip_p0_req     # Did we already request p0?
    sw      $s0, PUZZLE_REQUEST         # if we haven't, request and mark that we did
    sw      $v0, p0_ready
skip_p0_req:
    bne     $t1, $zero, skip_p1_req     # Did we already request p1?
    sw      $s1, PUZZLE_REQUEST         # if we haven't, request and mark that we did
    sw      $v0, p1_ready
skip_p1_req:
    lw      $t0, p0_ready               # load the flags for p0 and p1
    lw      $t1, p1_ready
    beq     $t0, $v1, pre_solve0        # solve whichever puzzle is ready
    beq     $t1, $v1, pre_solve1
    j       skip_p1_req                 # wait until one of the puzzles become ready
    
pre_solve0:                             # set up for solving puzzle0
    move    $s2, $s0                    # s2 = address of puzzle to be solved
    sw      $zero, p0_ready             # clear appropriate flags
    j       solve_prologue
pre_solve1:                             # set up for solving puzzle1
    move    $s2, $s1
    sw      $zero, p1_ready
solve_prologue:
    move    $s3, $s2                    # s3 = copy of the address of puzzle head
solve_loop:
    lw      $a0, str($s2)               # get the first string
    lw      $a1, str+4($s2)             # get the second string 
    jal     puzzle_solve                # solve the puzzle
    sw      $v0, solution($s2)          # store the puzzle
    add     $s7, $s7, 1                 # keeps track of puzzles solve
    lw      $s2, next($s2)              # go to the next puzzle
    bne     $s2, 0, solve_loop          # solve until a null pointer

    sw      $s3, SOLVE_REQUEST          # Turn in puzzle solutions
    bgt     $s7, 7, landing             # Go to another planet if solved 7 puzzles on this planet

    j       solve_dispatch              # otherwise go solve the next set

landing:
    add     $s6, $s6, 1
    bne     $s6, 5, take_off            # if target is not 5, go ahead and calculate offset
    move    $s6, $zero                  # otherwise target is planet 0 again
take_off:
    sw      $zero, TAKEOFF_REQUEST
    mul     $t0, $s6, planet_info_size  # land on the one specified by s6

    la      $t1, planets                # $t1 = start of planets array
    sw      $t1, PLANETS_REQUEST
    add     $t0, $t1, $t0               # $t0 = start of destination planet info

    lw      $t2, planet_x($t0)          # get planet x coordinate
    lw      $t3, planet_y($t0)          # get planet y coordinate
    lw      $t4, orbital_radius($t0)
                                        # select position to move
    li      $t5, 150
    blt     $t2, 150, leftQuad          # if planet_x is less than 150, planet in left quad
    j       rightQuad                                         
leftQuad:                             
    blt     $t3, 150, point1            # y<=150
point4:                               
    sub     $a0, $t5, $t4               # x=150-radius
    li      $a1, 150                    # y=150
    j       moveToPlanet
point1:
    li      $a0, 150                    # x=150
    sub     $a1, $t5, $t4               # y=150-radius
    j       moveToPlanet 
rightQuad:
    blt     $t3, 150, point2
point3:
    li      $a0, 150                    # x=150
    add     $a1, $t5, $t4               # y=150+radius
    j       moveToPlanet
point2:
    add     $a0, $t5, $t4               # x=150+radius
    li      $a1, 150

moveToPlanet:
    jal     move_sbot
    j       pre_puzzle:


####################################
#            KERNEL DATA           #
####################################
.kdata                                  # interrupt handler data (separated just for readability)
chunkIH:    .space 8                    # space for two registers
non_intrpt_str:     .asciiz "Non-interrupt exception\n"
unhandled_str:      .asciiz "Unhandled interrupt type\n"

.ktext 0x80000180
interrupt_handler:
.set noat
    move    $k1, $at                    # Save $at                               
.set at     
    la      $k0, chunkIH      
    sw      $a0, 0($k0)                 # Get some free registers                  
    sw      $v0, 4($k0)                 # by storing them to a global variable     
            
    mfc0    $k0, $13                    # Get Cause register                       
    srl     $a0, $k0, 2                        
    and     $a0, $a0, 0xf               # ExcCode field                            
    bne     $a0, 0, non_intrpt                 
        
interrupt_dispatch:                     # Interrupt:                             
    mfc0    $k0, $13                    # Get Cause register, again                 
    beq     $k0, 0, done                # handled all outstanding interrupts     

    and     $a0, $k0, TIMER_MASK        # is there a timer interrupt?                
    bne     $a0, 0, timer_interrupt   
    
    and     $a0, $k0, DELIVERY_MASK     # is there a puzzle delivery interrupt?                
    bne     $a0, 0, delivery_interrupt   

    li      $v0, PRINT_STRING           # Unhandled interrupt types
    la      $a0, unhandled_str
    syscall 
    j       done

timer_interrupt:
    sw      $zero, TIMER_ACKNOWLEDGE
    la      $v0, puzzle0
    la      $a0, puzzle1
    sw      $v0, SOLVE_REQUEST
    sw      $a0, SOLVE_REQUEST
    j       interrupt_dispatch
    
delivery_interrupt:
    sw      $zero, DELIVERY_ACKNOWLEDGE
    li      $v0, 2
    lw      $k0, p1_ready
    beq     $k0, $zero, not_p1_req
    sw      $v0, p1_ready
not_p1_req:
    lw      $k0, p0_ready
    beq     $k0, $zero, not_p0_req
    sw      $v0, p0_ready
not_p0_req:
    j       interrupt_dispatch

non_intrpt:                             # was some non-interrupt
    li      $v0, PRINT_STRING
    la      $a0, non_intrpt_str
    syscall                             # print out an error message
    # fall through to done

done:
    la      $k0, chunkIH
    lw      $a0, 0($k0)                 # Restore saved registers
    lw      $v0, 4($k0)
.set noat
    move    $at, $k1                    # Restore $at
.set at 
    eret


####################################
#          HELPER FUNCTIONS        #
####################################
.text
move_sbot:                              # FUNCTION: move_spimbot(target_x, target_y)
    sw      $ra, TAKEOFF_REQUEST($0)    # Request takeoff (write something to addr)
    li      $v0, 1                      # Load a constant 1 for absolute angle orientation
    li      $v1, 10                     # Load a constant 10 for velocity

align_x:                                # ALIGN X-POSITION
    lw      $t0, BOT_X($0)              # t0 = bot_x
    beq     $t0, $a0, align_y           # If x already aligned, skip to align_y
    move    $a2, $0                     # a2 = angle to face, default is right
    bgt     $a0, $t0, correct_xdir      # If target_x > bot_x, stay facing right
    add     $a2, $a2, 180               # otherwise face left
correct_xdir:
    sw      $a2, ANGLE($0)              # Angle = 0 or 180
    sw      $v0, ANGLE_CONTROL($0)      # Make spimbot face that angle
    sw      $v1, VELOCITY($0)           # velocity = 10
move_x:
    lw      $t0, BOT_X($0)              # t0 = bot_x
    bne     $t0, $a0, move_x            # if bot_x =/= target_x, keep moving 
    sw      $0,  VELOCITY($0)           # else stop moving 

align_y:                                # ALIGN Y-POSITION
    lw      $t1, BOT_Y($0)              # t1 = bot_y
    beq     $t1, $a1, landing           # If y already aligned, skip to landing
    li      $a2, 90                     # Default angle is down
    bgt     $a1, $t1, correct_ydir      # If target_y > bot_y, stay facing down
    add     $a2, $a2, 180               # otherwise face up
correct_ydir:
    sw      $a2, ANGLE($0)              # Angle = 90 or 270
    sw      $v0, ANGLE_CONTROL($0)      # Make spimbot face that angle
    sw      $v1, VELOCITY($0)           # velocity = 10
move_y:
    lw      $t1, BOT_Y($0)              # t1 = bot_y
    bne     $t1, $a1, move_y            # if bot_y =/= target_y, keep moving
    sw      $0,  VELOCITY($0)           # else stop moving

landing:                                # LANDING
    sw      $ra, LANDING_REQUEST($0)    # Attempt to land
    lw      $v0, LANDING_REQUEST($0)    # Did we land?
    blt     $v0, $0, landing            # If not, try again
    jr      $ra

####################################
# COPY-PASTED FROM LAB 7 SOLUTIONS #
####################################

puzzle_solve:
    sub     $sp, $sp, 20
    sw      $ra, 0($sp)                 # save $ra and free up 4 $s registers for
    sw      $s0, 4($sp)                 # str1
    sw      $s1, 8($sp)                 # str2
    sw      $s2, 12($sp)                # length
    sw      $s3, 16($sp)                # i

    move    $s0, $a0                    # str1
    move    $s1, $a1                    # str2

    jal     my_strlen

    move    $s2, $v0                    # length
    li      $s3, 0                      # i = 0
ps_loop:
    bgt     $s3, $s2, ps_return_minus_1
    move    $a0, $s0                    # str1
    move    $a1, $s1                    # str2
    jal     my_strcmp
    beq     $v0, $0, ps_return_i
    
    move    $a0, $s1                    # str2
    jal     rotate_string_in_place_fast
    add     $s3, $s3, 1                 # i ++
    j       ps_loop

ps_return_minus_1:
    li      $v0, -1
    j       ps_done

ps_return_i:
    move    $v0, $s3

ps_done:    
    lw      $ra, 0($sp)                 # restore registers and return
    lw      $s0, 4($sp)
    lw      $s1, 8($sp)
    lw      $s2, 12($sp)
    lw      $s3, 16($sp)
    add     $sp, $sp, 20
    jr      $ra

my_strcmp:
    li      $t3, 0                      # i = 0
my_strcmp_loop:
    add     $t0, $a0, $t3               # &str1[i]
    lb      $t0, 0($t0)                 # c1 = str1[i]
    add     $t1, $a1, $t3               # &str2[i]
    lb      $t1, 0($t1)                 # c2 = str2[i]

    beq     $t0, $t1, my_strcmp_equal
    sub     $v0, $t0, $t1               # c1 - c2
    jr      $ra

my_strcmp_equal:
    bne     $t0, $0, my_strcmp_not_done
    li      $v0, 0
    jr      $ra

my_strcmp_not_done:
    add     $t3, $t3, 1                 # i ++
    j       my_strcmp_loop

rotate_string_in_place_fast:
    sub     $sp, $sp, 8
    sw      $ra, 0($sp)
    sw      $a0, 4($sp)

    jal     my_strlen
    move    $t0, $v0                    # length
    lw      $a0, 4($sp)
    lb      $t1, 0($a0)                 # was_first = str[0]
            
    div     $t3, $t0, 4                 # length_in_ints = length / 4;

    li      $t2, 0                      # i = 0
    move    $a1, $a0                    # making copy of 'str' for use in first loop
rsipf_loop1:
    bge     $t2, $t3, rsipf_loop2_prologue
    lw      $t4, 0($a1)                 # unsigned first_word = str_as_array_of_ints[i]
    lw      $t5, 4($a1)                 # unsigned second_word = str_as_array_of_ints[i+1]
    srl     $t6, $t4, 8                 # (first_word >> 8)
    sll     $t7, $t5, 24                # (second_word << 24)
    or      $t7, $t7, $t6               # combined_word = (first_word >> 8) | (second_word << 24)
    sw      $t7, 0($a1)                 # str_as_array_of_ints[i] = combined_word
    add     $t2, $t2, 1                 # i ++
    add     $a1, $a1, 4                 # str_as_array_of_inst ++
    j       rsipf_loop1        

rsipf_loop2_prologue:
    mul     $t2, $t3, 4
    add     $t2, $t2, 1                 # i = length_in_ints*4 + 1
rsipf_loop2:
    bge     $t2, $t0, rsipf_done2
    add     $t3, $a0, $t2               # &str[i]
    lb      $t4, 0($t3)                 # char c = str[i]
    sb      $t4, -1($t3)                # str[i - 1] = c
    add     $t2, $t2, 1                 # i ++
    j       rsipf_loop2        
    
rsipf_done2:
    add     $t3, $a0, $t0               # &str[length]
    sb      $t1, -1($t3)                # str[length - 1] = was_first
    lw      $ra, 0($sp)
    add     $sp, $sp, 8
    jr      $ra

my_strlen:
    li      $v0, 0                      # length = 0  (in $v0 'cause return val)
my_strlen_loop:     
    add     $t1, $a0, $v0               # &str[length]
    lb      $t2, 0($t1)                 # str[length]
    beq     $t2, $0, my_strlen_done
    
    add     $v0, $v0, 1                 # length ++
    j       my_strlen_loop

my_strlen_done:
    jr      $ra
