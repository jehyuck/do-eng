# Experiment 1-21 clean A/B plan

Exp121 preserves Exp120 policy, workload, frozen images, collector coverage gate, crossover order, and validity rules. It uses new EXP121 run IDs and a separate result root. The sole harness change is byte-preserving native Docker log capture with distinct stdout/stderr raw files, metadata, a combined convenience log, and an execution timeline written before log capture. No policy decision is made here.
