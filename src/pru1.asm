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
[VOP] Uses SCLK on P8_45 and CS on P8_46 to read out SPI data of ADCs
      and write out data to DAC
*/

.origin 0
.entrypoint TOP

#define DDR_START     r10
#define DDR_END       r11
#define DDR_SIZE      r12
#define WRITE_POINTER r13
#define SHARED_RAM    r14
#define SAMPLE        r15
#define BYTES_WRITTEN r16

//[VOP]
#define DAC_DATA      r17
#define DAC_POINTER   r18
#define ADC_SAMPLE    r19

#include "shared_header.h"

TOP:
  // Enable OCP master ports in SYSCFG register
  lbco r0, C4, 4, 4
  clr  r0, r0, 4
  sbco r0, C4, 4, 4

  mov SHARED_RAM, SHARED_RAM_ADDRESS

  // From shared RAM, grab the address of the shared DDR segment
  lbbo DDR_START, SHARED_RAM, OFFSET(Params.physical_addr), SIZE(Params.physical_addr)
  // And the size of the segment
  lbbo DDR_SIZE, SHARED_RAM, OFFSET(Params.ddr_len), SIZE(Params.ddr_len)

  add DDR_END, DDR_START, DDR_SIZE

  // Write out the initial values of bytes_written and shared_ptr before we
  // enter the loop and have to wait for the first rising clock edge.
  mov BYTES_WRITTEN, 0
  sbbo BYTES_WRITTEN, SHARED_RAM, OFFSET(Params.bytes_written), SIZE(Params.bytes_written)
  mov WRITE_POINTER, DDR_START
  sbbo WRITE_POINTER, SHARED_RAM, OFFSET(Params.shared_ptr), SIZE(Params.shared_ptr)

  // First sample will be invalid (always 0) due to the way the loops are laid out.
  mov SAMPLE, 0

  //[VOP] Setup DAC_DATA and DAC_POINTER hidden in last 3rd of shared mem
  //[VOP] This could easily go very wrong if not for the fact that all
  //[VOP] three devices get an equal amount of RAM addressed
  mov DAC_POINTER, DDR_END
  lbbo DAC_DATA, DAC_POINTER, 0, 2
  add DAC_POINTER, DAC_POINTER, 2
  
MAIN_LOOP:
  //[VOP] Wait for CS low (P8_44)
  wbc r31, 3

  //[VOP] Write out first bit of DAC (MSB)
  set r30.b4, DAC_DATA.b15
  lsl DAC_DATA, DAC_DATA, 1

DATA_ACQ:
  //[VOP] Wait for rising clock edge
  wbs r31, 1

  //[VOP] Read out ADCs
  //[VOP] Set ADC samples from ADC_SAMPLE dummy because set doesn't work with r31 as source
  //[VOP] Read channel 0 (P8_27) into the lower half of the sample register 
  mov ADC_SAMPLE.w0, r31.b8 
  set SAMPLE.b0, ADC_SAMPLE.b0

  //[VOP] Read channel 1 (P8_39) into the higher half of the sample register 
  mov ADC_SAMPLE.w2, r31.b6
  set SAMPLE.b32, ADC_SAMPLE.b32

  //[VOP] Write out bits of DAC (r30.b4 = P8_41)
  //[VOP] In total, 17 bits will be send. Shouldn't be a problem cuz CS high before last bit arrives.
  set r30.b4, DAC_DATA.b15

  //[VOP] Wait for falling clock edge
  wbc r31, 1

  //[VOP] From here, we have only 30ns before CS may switch, 
  //[VOP] so only space for 5 instructions lest we create a race condition

  //[VOP] Shift all registers left so that next bit lines up
  lsl SAMPLE, SAMPLE, 1
  lsl DAC_DATA, DAC_DATA, 1

  //[VOP] Check if CS high, otherwise loop
  qbbc DATA_ACQ, r31, 3

  //[VOP] Shift ADC registers right by 3, cuz last three samples "invalid"
  //[VOP] From specs: 2 leading zeros + 1 extra due to pulldown
  //[VOP] This assumes data has been acquired for 16 clockcycles
  lsr SAMPLE, SAMPLE, 3


  // sbbo generally takes (1 + word count) cycles, so 2 in this case,
  // but can also take longer in the case of bus collisions.
  //[VOP] We have 4*200Mhz/SCLK >= 80 cycles to run this part, which should be more than enough 
  sbbo SAMPLE, WRITE_POINTER, 0, 4

  sbbo WRITE_POINTER, SHARED_RAM, OFFSET(Params.shared_ptr), SIZE(Params.shared_ptr)

  //[VOP] load DAC data
  lbbo DAC_DATA, SHARED_RAM, DAC_POINTER, 2
  add DAC_POINTER, DAC_POINTER, 2


  // Now we use our delay downtime to manage the counters
  add WRITE_POINTER, WRITE_POINTER, 4
  add BYTES_WRITTEN, BYTES_WRITTEN, 4
  sbbo BYTES_WRITTEN, SHARED_RAM, OFFSET(Params.bytes_written), SIZE(Params.bytes_written)

  // If we wrapped, reset the pointer to the start of the buffer.
  qblt DIDNT_WRAP, DDR_END, WRITE_POINTER
  mov WRITE_POINTER, DDR_START
  mov DAC_POINTER, DDR_END

DIDNT_WRAP:

  qba MAIN_LOOP

// We loop forever, but I always end with halt so that I never forget.
halt
