#!/usr/bin/env python3
# smp0.py SRC -- experiment 0 for a dual-CPU mac99: allow two CPUs, the second held powered off at reset (as a
# dual G4's is until the system releases it). Nothing yet releases it.
import sys
p = sys.argv[1] + '/hw/ppc/mac_newworld.c'
s = open(p).read()
def one(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a)
    s = s.replace(a, b)
one("""    cpu_reset(CPU(cpu));
    /* 970 CPUs want to get their initial IP as part of their boot protocol */
    cpu->env.nip = PROM_BASE + 0x100;
}""", """    cpu_reset(CPU(cpu));
    /* 970 CPUs want to get their initial IP as part of their boot protocol */
    cpu->env.nip = PROM_BASE + 0x100;
    /* AOK VM: a second CPU waits, as on a dual G4, until it is released */
    if (CPU(cpu)->cpu_index > 0) {
        CPU(cpu)->halted = 1;
        cpu_interrupt(CPU(cpu), CPU_INTERRUPT_HALT);
    }
}""")
one("""    /* SMP is not supported currently */
    mc->max_cpus = 1;""", """    /* AOK VM: two, for work on a dual G4 (the second is held at reset) */
    mc->max_cpus = 2;""")
open(p, 'w').write(s)
print('applied')
# The OpenPIC: an output set for each CPU, each wired to its own CPU (upstream wires every set to the last CPU
# created, which for one CPU is the same thing).
s = open(p).read()
one("""    macio = OBJECT(pci_new(-1, TYPE_NEWWORLD_MACIO));
""", """    macio = OBJECT(pci_new(-1, TYPE_NEWWORLD_MACIO));
    qdev_prop_set_uint32(DEVICE(object_resolve_path_component(macio, "pic")),
                         "nb_cpus", machine->smp.cpus);
""")
one("""    openpic_irqs = g_new0(IrqLines, machine->smp.cpus);
    dev = DEVICE(cpu);
    for (i = 0; i < machine->smp.cpus; i++) {
""", """    openpic_irqs = g_new0(IrqLines, machine->smp.cpus);
    for (i = 0; i < machine->smp.cpus; i++) {
        dev = DEVICE(qemu_get_cpu(i));
        env = &POWERPC_CPU(dev)->env;
""")
open(p, 'w').write(s)
print('openpic per CPU')
