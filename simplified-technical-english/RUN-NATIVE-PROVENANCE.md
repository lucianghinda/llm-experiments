# run-native: the independent Codex replication

## What it is

`run-1` and `run-2` were both executed by me (Claude) driving `codex exec` from a shell.
`run-native` is different: **Codex was asked to run the Codex arm of these experiments
itself**, independently, and produced the twelve files now in each `*/run-native/` folder.

Codex wrote those twelve files into its own working folder. They were copied here
verbatim, byte for byte, and that folder was then removed. The files in `*/run-native/`
are the only surviving originals.

## Why it matters

Run 1 and run 2 share a harness. If my invocation of `codex exec` was doing something
unintended, both runs would carry the same error and repeating it would not reveal that.
An arm executed by a different driver breaks that shared dependency.

## What is not controlled

I did not run this arm and do not know its exact invocation: model, reasoning effort,
sandbox mode, or whether the working directory and config matched mine. The outputs are
noticeably terser than mine in most cells, for example 93 prose words against my 146 and 158
on experiment 3's control. So treat `run-native` as an **independent replication of the
question**, not as a third sample from the same harness.

Only the Codex arm exists here. There is no Claude arm in `run-native`, so the coverage and
metrics tables show `.` for those cells rather than a zero.

## What it confirmed

Codex content coverage, out of 24 facts:

| | run-1 | run-2 | run-native |
|---|---|---|---|
| control | 17 | 13 | 13 |
| Simple Technical English | 7 | 10 | 6 |
| ASD-STE100 | 10 | 8 | 7 |

Both style clauses cost Codex content in all three runs, from a different driver. This is
the Codex conclusion I held most loosely after two runs, and it now has independent support.

## What it corrected

After two runs I wrote that Simple Technical English made Codex's sentences *longer* than its
own control "in five of eight runs". That was wrong twice over. Counting properly:

- Across run-1 and run-2 it was **4 of 8**, not 5.
- Adding run-native it is **4 of 12**, because the native arm shortened Codex's sentences in
  all four of its targets.

The corrected statement is that ASD-STE100 shortens Codex reliably (12 of 12 runs) while
Simple Technical English does not (8 of 12, and it lengthens them in the other 4).

## An outlier worth noting

`02-single-method-domain/run-native/codex-1-control.md` averages 25.5 words per sentence with
33% of sentences over the 25-word limit. That is the longest Codex control in the whole set,
and the largest single drop from adding a clause anywhere in the data, down to 9.0. One cell,
so I would not build anything on it.
