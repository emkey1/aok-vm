#!/usr/bin/env python3
# smp1.py TREE -- a dual-CPU mac99 (a dual G4, as Mac OS X starts one): the OpenPIC per CPU, CPU 1 held at reset
# until KeyLargo's GPIO 0x5C strobes its SRESET, GPIO 0x73 as every CPU's timebase enable, and CPU 1's device
# node copied from CPU 0's by an nvramrc script that OpenBIOS runs after building its tree.
import sys
T = sys.argv[1]
def edit(path, pairs):
    p = T + '/' + path; s = open(p).read()
    for a, b in pairs:
        assert s.count(a) == 1, (path, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w').write(s)

edit('include/hw/misc/macio/gpio.h', [(
"""    uint8_t gpio_regs[36]; /* XXX Check count */
};""",
"""    uint8_t gpio_regs[36]; /* XXX Check count */
    /* KeyLargo's SRESET lines for CPU 0 and 1 (GPIOs 0x5B, 0x5C), high while asserted */
    qemu_irq cpu_sreset[2];
    /* the timebase enable (GPIO 0x73), high while the timebases run */
    qemu_irq tb_enable;
};""")])

edit('hw/misc/macio/gpio.c', [(
"""        s->gpio_regs[addr] = value | ibit;
    }
}""",
"""        s->gpio_regs[addr] = value | ibit;

        /*
         * The lines a dual-processor machine uses (Apple's MacRISC2CPU):
         * SRESET for CPU 0 and 1 (offsets 0x5B, 0x5C) and the timebase
         * enable (0x73) are open collectors, driven low by making the GPIO
         * an output with a data bit of 0, and high (released) otherwise.
         */
        switch (addr) {
        case 0x5b - 0x58:
        case 0x5c - 0x58:
            qemu_set_irq(s->cpu_sreset[addr - (0x5b - 0x58)],
                         (value & (OUT_ENABLE | OUT_DATA)) == OUT_ENABLE);
            break;
        case 0x73 - 0x58:
            qemu_set_irq(s->tb_enable,
                         (value & (OUT_ENABLE | OUT_DATA)) != OUT_ENABLE);
            break;
        }
    }
}"""), (
"""    memory_region_init_io(&s->gpiomem, OBJECT(s), &macio_gpio_ops, obj,
                          "gpio", 0x30);""",
"""    qdev_init_gpio_out_named(DEVICE(obj), s->cpu_sreset, "cpu-sreset", 2);
    qdev_init_gpio_out_named(DEVICE(obj), &s->tb_enable, "timebase-enable", 1);

    memory_region_init_io(&s->gpiomem, OBJECT(s), &macio_gpio_ops, obj,
                          "gpio", 0x30);""")])

edit('hw/intc/openpic.c', [(
"""        if (opp->nb_cpus != 1) {
            error_setg(errp, "Only UP supported today");
            return;
        }""",
"""        /* a dual G4's KeyLargo MPIC serves two CPUs */
        if (opp->nb_cpus > 2) {
            error_setg(errp, "KeyLargo's MPIC serves at most two CPUs");
            return;
        }""")])

edit('hw/ppc/mac_newworld.c', [(
"""static void ppc_core99_reset(void *opaque)
{
    PowerPCCPU *cpu = opaque;

    cpu_reset(CPU(cpu));
    /* 970 CPUs want to get their initial IP as part of their boot protocol */
    cpu->env.nip = PROM_BASE + 0x100;
}""",
"""static void ppc_core99_reset(void *opaque)
{
    PowerPCCPU *cpu = opaque;

    cpu_reset(CPU(cpu));
    /* 970 CPUs want to get their initial IP as part of their boot protocol */
    cpu->env.nip = PROM_BASE + 0x100;
    /* the timebase runs until KeyLargo's GPIO 0x73 stops it */
    if (PPC_INPUT(&cpu->env) == PPC_FLAGS_INPUT_6xx) {
        qemu_irq_raise(qdev_get_gpio_in(DEVICE(cpu), PPC6xx_INPUT_TBEN));
    }
    /*
     * On a dual G4 the second CPU does nothing until the system strobes its
     * SRESET line (ppc_core99_cpu_sreset); the firmware runs on the first.
     */
    if (CPU(cpu)->cpu_index > 0) {
        /*
         * Halted, with no request to halt pending: such a request would be
         * taken the first time the CPU runs, which is right after its
         * release, and halt it again.
         */
        CPU(cpu)->halted = 1;
    }
}

/*
 * KeyLargo's SRESET line for a CPU other than the first, asserted: the CPU
 * takes a system reset exception at 0x100, with its exception prefix at 0 as
 * the boot ROM leaves a parked CPU's, which is where Mac OS X has put its
 * reset handler (MacRISC2CPU::startCPU, start_paddr 0x100). The first CPU's
 * line is not wired: a soft reset of the running CPU is not something the
 * firmware or Mac OS X asks for.
 */
static void ppc_core99_sreset_on_cpu(CPUState *cs, run_on_cpu_data data)
{
    CPUPPCState *env = cpu_env(cs);

    env->msr &= ~((target_ulong)1 << MSR_EP);
    env->excp_prefix = 0;
    cpu_reset_interrupt(cs, CPU_INTERRUPT_HALT);
    ppc_cpu_do_system_reset(cs);
}

static void ppc_core99_cpu_sreset(void *opaque, int n, int level)
{
    CPUState *cs = qemu_get_cpu(n);

    if (level && n > 0 && cs) {
        async_run_on_cpu(cs, ppc_core99_sreset_on_cpu, RUN_ON_CPU_NULL);
    }
}

/* KeyLargo's timebase enable: every CPU's TBEN input (frozen while low) */
static void ppc_core99_tb_enable(void *opaque, int n, int level)
{
    CPUState *cs;

    CPU_FOREACH(cs) {
        if (PPC_INPUT(cpu_env(cs)) == PPC_FLAGS_INPUT_6xx) {
            qemu_set_irq(qdev_get_gpio_in(DEVICE(cs), PPC6xx_INPUT_TBEN),
                         level);
        }
    }
}

/*
 * OpenBIOS describes one CPU. With more, an nvramrc script that it evaluates
 * after building its tree adds the second CPU's node under /cpus: a copy of
 * the first's properties with reg 1 and a state that is not "running", which
 * is how Mac OS X tells the boot CPU from the others (MacRISC2CPU::start).
 * Not "available" and "translations": the first CPU's node is OpenBIOS's MMU
 * package, and those are its, kept up to date there.
 */
static const char ppc_core99_cpu1_nvramrc[] =
    "nvramrc=: aok-cpu1 \\" /cpus\\" find-package 0= if exit then "
    "child ?dup 0= if exit then >r \\" /cpus\\" find-device new-device "
    "0 0 begin r@ next-property while "
    "2dup \\" reg\\" $= >r 2dup \\" state\\" $= r> or "
    ">r 2dup \\" available\\" $= r> or >r 2dup \\" translations\\" $= r> or "
    "0= if "
    "2dup r@ get-package-property 0= if 2over property then then "
    "repeat r> drop "
    "1 encode-int \\" reg\\" property "
    "\\" stopped\\" encode-string \\" state\\" property "
    "finish-device device-end ; aok-cpu1";"""), (
"""    /* init CPUs */
    for (i = 0; i < machine->smp.cpus; i++) {""",
"""    if (machine->smp.cpus > 1) {
        bool has_rc = false;

        for (i = 0; i < nb_prom_envs; i++) {
            has_rc |= g_str_has_prefix(prom_envs[i], "nvramrc=");
        }
        if (has_rc || nb_prom_envs + 2 > MAX_PROM_ENVS) {
            warn_report("mac99: an nvramrc of the user's own: the second "
                        "CPU will not be described to the guest");
        } else {
            prom_envs[nb_prom_envs++] = "use-nvramrc?=true";
            prom_envs[nb_prom_envs++] = ppc_core99_cpu1_nvramrc;
        }
    }

    /* init CPUs */
    for (i = 0; i < machine->smp.cpus; i++) {"""), (
"""    macio = OBJECT(pci_new(-1, TYPE_NEWWORLD_MACIO));
""",
"""    macio = OBJECT(pci_new(-1, TYPE_NEWWORLD_MACIO));
    qdev_prop_set_uint32(DEVICE(object_resolve_path_component(macio, "pic")),
                         "nb_cpus", machine->smp.cpus);
"""), (
"""    openpic_irqs = g_new0(IrqLines, machine->smp.cpus);
    dev = DEVICE(cpu);
    for (i = 0; i < machine->smp.cpus; i++) {
""",
"""    openpic_irqs = g_new0(IrqLines, machine->smp.cpus);
    for (i = 0; i < machine->smp.cpus; i++) {
        /* each CPU's own inputs (upstream wired every set to the last CPU) */
        dev = DEVICE(qemu_get_cpu(i));
        env = &POWERPC_CPU(dev)->env;
"""), (
"""    /* SMP is not supported currently */
    mc->max_cpus = 1;""",
"""    /* a dual G4 (PowerMac3,3 and later): two */
    mc->max_cpus = 2;""")])
print('applied')
# KeyLargo's GPIOs to the CPUs: wired before the Mac I/O device is realized (a GPIO output's link is set only
# then). The GPIO block is the PMU machine's; without it a second CPU could never be started.
edit('hw/ppc/mac_newworld.c', [(
"""    qdev_prop_set_bit(dev, "has-pmu", has_pmu);
    qdev_prop_set_bit(dev, "has-adb", has_adb);
""",
"""    qdev_prop_set_bit(dev, "has-pmu", has_pmu);
    qdev_prop_set_bit(dev, "has-adb", has_adb);
    if (has_pmu) {
        DeviceState *gpio = DEVICE(object_resolve_path_component(macio,
                                                                 "gpio"));

        for (i = 0; i < 2; i++) {
            qdev_connect_gpio_out_named(gpio, "cpu-sreset", i,
                qemu_allocate_irq(ppc_core99_cpu_sreset, NULL, i));
        }
        qdev_connect_gpio_out_named(gpio, "timebase-enable", 0,
            qemu_allocate_irq(ppc_core99_tb_enable, NULL, 0));
    } else if (machine->smp.cpus > 1) {
        error_report("mac99: a second CPU needs the PMU machine "
                     "(via=pmu or via=pmu-adb): its GPIOs start it");
        exit(1);
    }
""")])
print('gpio wired')
edit('hw/ppc/mac_newworld.c', [(
"""#include "system/system.h"
""",
"""#include "system/system.h"
#include "hw/core/irq.h"
""")])
print('irq.h')
