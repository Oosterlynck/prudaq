// -*- mode: asm -*-
/*
Copyright 2015 Google Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied.  See the License for the specific language governing
permissions and limitations under the License.
*/

/*
This generates an ADC clock using GPIO pin P9_31.

[VOP] Also generates the CS signal for SPI control using GPIO pin P9_29.
      Cycle is hardcoded on 16 pulses low, 4 pulses high.
      So runs at Fclk/20 sample rate.
*/

.origin 0
.entrypoint TOP

#include "shared_header.h"

// How many cycles in the "on" pulse
#define HIGH_COUNT   r20
// Counts down from HIGH_COUNT
#define HIGH_COUNTER r21
// Entry point into the loop depending whether HIGH_COUNT is odd or even
#define HIGH_START   r22

#define LOW_COUNT    r23
#define LOW_COUNTER  r24
#define LOW_START    r25

//[VOP] Hopefully works, didn't check if r26 used
#define CS_COUNTER   r26

#define SHARED_RAM   r29

#define NOP add r0, r0, 0

TOP:
  // Enable OCP master ports in SYSCFG register
  lbco r0, C4, 4, 4
  clr  r0, r0, 4
  sbco r0, C4, 4, 4

  mov SHARED_RAM, SHARED_RAM_ADDRESS
  lbbo HIGH_COUNT, SHARED_RAM, OFFSET(Params.high_cycles), SIZE(Params.high_cycles)
  lbbo LOW_COUNT, SHARED_RAM, OFFSET(Params.low_cycles), SIZE(Params.low_cycles)
  //[VOP] initializes P9_29 (CS) on high
  lbbo r30, SHARED_RAM, OFFSET(Params.input_select), SIZE(Params.input_select)

  mov HIGH_COUNTER, HIGH_COUNT
  mov LOW_COUNTER, LOW_COUNT


  //[VOP] Best way I found to make sure CS_COUNTER starts on 0
  //[VOP] Clears r26 (4 bytes).
  //[VOP] May be unneeded if registers init on 0.
  zero &CS_COUNTER, 4

  // The loop decrements by 2, so we need to start a cycle early
  // if the count is odd.  Store the appropriate starting address
  // in LOW_START
  mov LOW_START, CYCLE_ODD_L
  QBBS CYCLE_L_IS_ODD, LOW_COUNTER, 0
  mov LOW_START, CYCLE_EVEN_L
CYCLE_L_IS_ODD:

  // Repeat for HIGH_START
  mov HIGH_START, CYCLE_ODD_H
  QBBS CYCLE_H_IS_ODD, HIGH_COUNTER, 0
  mov HIGH_START, CYCLE_EVEN_H
  QBA CYCLE_EVEN_H
CYCLE_H_IS_ODD:

  // Main loop starts here (or at CYCLE_EVEN_H if HIGH_COUNT is even)

CYCLE_ODD_H:
  sub HIGH_COUNTER, HIGH_COUNTER, 1
CYCLE_EVEN_H:
  //NOP

  //[VOP] Add to CS counter
  add CS_COUNTER, CS_COUNTER, 1
  sub HIGH_COUNTER, HIGH_COUNTER, 2

  //[VOP] GPIO clock pin P9_29 goes low after 4 SCLK cycles
  qble WAIT_H, CS_COUNTER, 4
  //[VOP] CS goes low 15 or 20ns after SCLK goes high, costs 2 cycles
  sub HIGH_COUNTER, HIGH_COUNTER, 2
  clr r30, 1
  

WAIT_H:
  sub HIGH_COUNTER, HIGH_COUNTER, 2
  qblt WAIT_H, HIGH_COUNTER, 4

  // Reset the count for the low half of the cycle
  mov LOW_COUNTER, LOW_COUNT

  // GPIO clock pin P9_31 goes low
  clr r30, 0

  // Jump to CYCLE_ODD_L or CYCLE_EVEN_L
  JMP LOW_START

CYCLE_ODD_L:
  sub LOW_COUNTER, LOW_COUNTER, 1
CYCLE_EVEN_L:
  //NOP

  //[VOP] GPIO clock pin P9_29 goes high after 20 SCLK cycles
  qblt WAIT_L, CS_COUNTER, 20
  //[VOP] CS goes high 20 or 25ns after SCLK goes low, costs 3 cycles, but force even => 4
  sub LOW_COUNTER, LOW_COUNTER, 4
  sub CS_COUNTER, CS_COUNTER, 20
  NOP
  set r30, 1
  
WAIT_L:
  sub LOW_COUNTER, LOW_COUNTER, 2
  qblt WAIT_L, LOW_COUNTER, 4

  // Reset the count for the high half of the cycle
  mov HIGH_COUNTER, HIGH_COUNT

  // GPIO clock pin P9_31 goes high
  set r30, 0


  // Start the cycle over, skipping CYCLE_ODD_H if the count is even
  JMP HIGH_START
