typedef uint64_t u64;

#define __stringify_1(x...)     #x
#define __stringify(x...)       __stringify_1(x)
#define __emit_inst(x)                  ".inst " __stringify((x)) "\n\t"

asm(
"       .irp    num,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30\n"
"       .equ    .L__reg_num_x\\num, \\num\n"
"       .endr\n"
"       .equ    .L__reg_num_xzr, 31\n"
"\n"
"       .macro  mrs_s, rt, sreg\n"
        __emit_inst(0xd5200000|(\\sreg)|(.L__reg_num_\\rt))
"       .endm\n"
"\n"
"       .macro  msr_s, sreg, rt\n"
        __emit_inst(0xd5000000|(\\sreg)|(.L__reg_num_\\rt))
"       .endm\n"
);

#define Op0_shift       19
#define Op0_mask        0x3
#define Op1_shift       16
#define Op1_mask        0x7
#define CRn_shift       12
#define CRn_mask        0xf
#define CRm_shift       8
#define CRm_mask        0xf
#define Op2_shift       5
#define Op2_mask        0x7

#define sys_reg(op0, op1, crn, crm, op2) \
        (((op0) << Op0_shift) | ((op1) << Op1_shift) | \
         ((crn) << CRn_shift) | ((crm) << CRm_shift) | \
         ((op2) << Op2_shift))

#define write_sysreg(v, r) do {                                 \
        u64 __val = (u64)(v);                                   \
        asm volatile("msr " __stringify(r) ", %x0"              \
                     : : "rZ" (__val));                         \
} while (0)

#define write_sysreg_s(v, r) do {                                       \
        u64 __val = (u64)(v);                                           \
        asm volatile("msr_s " __stringify(r) ", %x0" : : "rZ" (__val)); \
} while (0)

#define PVR7F6_EL0 sys_reg(3, 7, 15, 15, 6)
#define PVR7F7_EL0 sys_reg(3, 7, 15, 15, 7)

inline void
trigger_waves(void) {
   write_sysreg_s(1, PVR7F6_EL0);
   //printf("WAVE TRIGGERED\n");
}

/* Should call write_sysreg_s(0, PVR7F6_EL0) at the end to reset */
