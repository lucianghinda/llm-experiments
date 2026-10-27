# Investigation task

You are reviewing a small Ruby payment-processing service. A customer reports that retrying a checkout occasionally creates two charges for the same order. Diagnose the most likely failure from the supplied code, explain the interleaving that causes it, and propose the smallest production-worthy correction.

Please provide:

1. The specific unsafe assumption or operation and a concrete concurrent execution timeline.
2. A correction that remains safe when two requests for the same order overlap, including what must be atomic and what database constraint or transaction boundary is needed.
3. How retries after an uncertain response should behave, and one focused regression test that would distinguish the defect from the corrected behavior.
4. Any important limitation or tradeoff in your proposed fix.

Use only the supplied code as evidence. Do not assume an external payment provider API contract that is not stated. The code is a deliberately small, dependency-free reproduction of a common Ruby/Rails service pattern; you do not need Rails installed.
