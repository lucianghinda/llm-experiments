# Trial comparison report

This is a diagnostic index of every recorded attempt. Fake-adapter rows are retained for auditability but excluded from research data. Counts describe changed files and text lines; they are not quality scores. No winner is selected and no statistical inference is made.
The attempts table is not the assigned-cell denominator. Actual continuation turns under a cell are part of that existing cell; the final continuation code and agent time are included in the cell comparison. Separate `continuation_smoke` audit tasks are excluded.

Token and cost values are reported only when present in aggregate usage events; a Codex field is summed only when every completed turn provides it. Missing values are `unknown`, never zero. Codex input tokens already include cached input; cache-read and cache-write counts are subsets, not additional input. Claude reports cache categories separately. Do not sum token categories across providers. Transcript contents and absolute workspace paths are not included.

## Attempts

| Trial path | Task | Agent | Model | Condition | Track | Status | Incident | Eligibility | Checks | Restored | Agent seconds | Input tokens | Output tokens | Cache read | Cache creation | Cost (USD) | Research data |
|---|---|---|---|---|---|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|
| [0001/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0001/continuations/answer-01) | notification_digest | claude | claude-opus-5 | baseline | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 67.33298199996352 | 12 | 6025 | 185053 | 8928 | 0.6535205000000001 | included via existing cell |
| [0001](../../results-raw/contrast-v2-20261102-stage1/0001) | notification_digest | claude | claude-opus-5 | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 61.58894099993631 | 14 | 4928 | 148998 | 12326 | 0.321029 | included |
| [0002/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0002/continuations/answer-01) | notification_digest | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 11.629724999889731 | 4 | 698 | 59412 | 3308 | 0.4672195 | included via existing cell |
| [0002](../../results-raw/contrast-v2-20261102-stage1/0002) | notification_digest | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 73.02353999996558 | 18 | 5038 | 212347 | 15475 | 0.3869635 | included |
| [0003](../../results-raw/contrast-v2-20261102-stage1/0003) | notification_digest | claude | claude-opus-5 | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 82.36855000024661 | 22 | 5725 | 316260 | 22949 | 0.5308550000000001 | included |
| [0004](../../results-raw/contrast-v2-20261102-stage1/0004) | notification_digest | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 69.23397399997339 | 18 | 5337 | 211653 | 15531 | 0.3946515 | included |
| [0005](../../results-raw/contrast-v2-20261102-stage1/0005) | notification_digest | claude | claude-opus-5 | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 64.96141400001943 | 12 | 4362 | 123346 | 11730 | 0.2880830000000001 | included |
| [0006](../../results-raw/contrast-v2-20261102-stage1/0006) | notification_digest | claude | claude-opus-5 | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 83.14495899993926 | 22 | 5807 | 321694 | 22689 | 0.533022 | included |
| [0007](../../results-raw/contrast-v2-20261102-stage1/0007) | notification_digest | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 34.329610999673605 | 14 | 2705 | 174156 | 15604 | 0.310813 | included |
| [0008](../../results-raw/contrast-v2-20261102-stage1/0008) | notification_digest | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 27.113708999939263 | 12 | 1995 | 117108 | 9512 | 0.20360899999999998 | included |
| [0009](../../results-raw/contrast-v2-20261102-stage1/0009) | notification_digest | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 46.3751030000858 | 16 | 3500 | 178741 | 14089 | 0.31784049999999997 | included |
| [0010](../../results-raw/contrast-v2-20261102-stage1/0010) | notification_digest | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 43.72625999990851 | 14 | 3260 | 151835 | 13512 | 0.29260749999999996 | included |
| [0011](../../results-raw/contrast-v2-20261102-stage1/0011) | notification_digest | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 23.995959000196308 | 12 | 1463 | 117017 | 9114 | 0.1862835 | included |
| [0012](../../results-raw/contrast-v2-20261102-stage1/0012) | notification_digest | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 50.466314000077546 | 18 | 3707 | 249638 | 20986 | 0.42744399999999994 | included |
| [0013/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0013/continuations/answer-01) | notification_digest | codex | gpt-6.1-sol | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 29.743986999616027 | 210863 | 1609 | 179328 | 0 | unknown | included via existing cell |
| [0013](../../results-raw/contrast-v2-20261102-stage1/0013) | notification_digest | codex | gpt-6.1-sol | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 23.541751000098884 | 89975 | 530 | 62976 | 0 | unknown | included |
| [0014](../../results-raw/contrast-v2-20261102-stage1/0014) | notification_digest | codex | gpt-6.1-sol | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 33.22853300021961 | 84067 | 1070 | 73472 | 0 | unknown | included |
| [0015](../../results-raw/contrast-v2-20261102-stage1/0015) | notification_digest | codex | gpt-6.1-sol | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 37.244001999963075 | 89122 | 1200 | 79744 | 0 | unknown | included |
| [0016](../../results-raw/contrast-v2-20261102-stage1/0016) | notification_digest | codex | gpt-6.1-sol | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 39.70117300003767 | 74134 | 1229 | 64896 | 0 | unknown | included |
| [0017](../../results-raw/contrast-v2-20261102-stage1/0017) | notification_digest | codex | gpt-6.1-sol | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 34.94609000021592 | 83096 | 1136 | 77568 | 0 | unknown | included |
| [0018/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0018/continuations/answer-01) | notification_digest | codex | gpt-6.1-sol | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 30.67633800022304 | 229533 | 1703 | 203904 | 0 | unknown | included via existing cell |
| [0018](../../results-raw/contrast-v2-20261102-stage1/0018) | notification_digest | codex | gpt-6.1-sol | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 30.562245999928564 | 90100 | 587 | 75136 | 0 | unknown | included |
| [0019](../../results-raw/contrast-v2-20261102-stage1/0019) | notification_digest | codex | gpt-6.1-sol | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 40.22209100006148 | 157227 | 1259 | 130688 | 0 | unknown | included |
| [0020](../../results-raw/contrast-v2-20261102-stage1/0020) | notification_digest | codex | gpt-6.1-sol | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 27.3817440001294 | 78885 | 979 | 71040 | 0 | unknown | included |
| [0021](../../results-raw/contrast-v2-20261102-stage1/0021) | notification_digest | codex | gpt-6.1-sol | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 27.729532999917865 | 74330 | 926 | 67200 | 0 | unknown | included |
| [0022](../../results-raw/contrast-v2-20261102-stage1/0022) | notification_digest | codex | gpt-6.1-sol | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 35.00418599974364 | 155630 | 1314 | 119168 | 0 | unknown | included |
| [0023](../../results-raw/contrast-v2-20261102-stage1/0023) | notification_digest | codex | gpt-6.1-sol | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 27.30324799986556 | 74908 | 837 | 67712 | 0 | unknown | included |
| [0024](../../results-raw/contrast-v2-20261102-stage1/0024) | notification_digest | codex | gpt-6.1-sol | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 25.24224100029096 | 78786 | 860 | 69248 | 0 | unknown | included |
| [0025/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0025/continuations/answer-01) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 19.11453599995002 | 2 | 1158 | 28666 | 1208 | 0.38626099999999997 | included via existing cell |
| [0025/continuations/answer-02](../../results-raw/contrast-v2-20261102-stage1/0025/continuations/answer-02) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 27.071688999887556 | 8 | 1558 | 127296 | 4074 | 0.529639 | included via existing cell |
| [0025](../../results-raw/contrast-v2-20261102-stage1/0025) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 67.38530199974775 | 12 | 4632 | 128996 | 15053 | 0.33088799999999996 | included |
| [0026/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0026/continuations/answer-01) | regional_policy | claude | claude-opus-5 | baseline | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 38.470313999801874 | 10 | 3094 | 141982 | 5634 | 0.500799 | included via existing cell |
| [0026](../../results-raw/contrast-v2-20261102-stage1/0026) | regional_policy | claude | claude-opus-5 | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 64.86347000021487 | 14 | 4137 | 146186 | 11948 | 0.296068 | included |
| [0027/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0027/continuations/answer-01) | regional_policy | claude | claude-opus-5 | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 27.556508000008762 | 8 | 2170 | 128324 | 5282 | 0.5035315 | included via existing cell |
| [0027](../../results-raw/contrast-v2-20261102-stage1/0027) | regional_policy | claude | claude-opus-5 | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 45.810794999822974 | 14 | 3159 | 175789 | 16532 | 0.3322595 | included |
| [0028/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0028/continuations/answer-01) | regional_policy | claude | claude-opus-5 | baseline | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 37.55787899997085 | 10 | 3012 | 136035 | 5625 | 0.46747350000000004 | included via existing cell |
| [0028](../../results-raw/contrast-v2-20261102-stage1/0028) | regional_policy | claude | claude-opus-5 | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 54.807678000070155 | 14 | 3550 | 143092 | 10749 | 0.26785600000000004 | included |
| [0029/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0029/continuations/answer-01) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 41.0348319998011 | 10 | 3101 | 145924 | 10144 | 0.49523599999999995 | included via existing cell |
| [0029](../../results-raw/contrast-v2-20261102-stage1/0029) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 60.84239100012928 | 10 | 3679 | 97508 | 10248 | 0.243259 | included |
| [0030/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0030/continuations/answer-01) | regional_policy | claude | claude-opus-5 | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 63.49492800002918 | 10 | 4750 | 175869 | 7892 | 0.671667 | included via existing cell |
| [0030](../../results-raw/contrast-v2-20261102-stage1/0030) | regional_policy | claude | claude-opus-5 | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 67.97717100009322 | 14 | 4873 | 177455 | 17539 | 0.38601250000000004 | included |
| [0031](../../results-raw/contrast-v2-20261102-stage1/0031) | regional_policy | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 62.011920999735594 | 16 | 4041 | 168413 | 11726 | 0.3025715 | included |
| [0032](../../results-raw/contrast-v2-20261102-stage1/0032) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 41.17157300002873 | 14 | 3096 | 153397 | 13710 | 0.2912685 | included |
| [0033](../../results-raw/contrast-v2-20261102-stage1/0033) | regional_policy | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 43.74254600005224 | 12 | 3881 | 148874 | 16737 | 0.33889199999999997 | included |
| [0034](../../results-raw/contrast-v2-20261102-stage1/0034) | regional_policy | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 72.29275299981236 | 24 | 4785 | 289187 | 16332 | 0.4276585 | included |
| [0035](../../results-raw/contrast-v2-20261102-stage1/0035) | regional_policy | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 38.42585999984294 | 14 | 3131 | 175060 | 16203 | 0.32790500000000006 | included |
| [0036](../../results-raw/contrast-v2-20261102-stage1/0036) | regional_policy | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 43.96264099981636 | 16 | 3334 | 164633 | 10848 | 0.27422650000000004 | included |
| [0037/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0037/continuations/answer-01) | regional_policy | codex | gpt-6.1-sol | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 25.010691000148654 | 196866 | 1099 | 167424 | 0 | unknown | included via existing cell |
| [0037](../../results-raw/contrast-v2-20261102-stage1/0037) | regional_policy | codex | gpt-6.1-sol | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 20.1777960001491 | 83143 | 356 | 64256 | 0 | unknown | included |
| [0038/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0038/continuations/answer-01) | regional_policy | codex | gpt-6.1-sol | baseline | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 19.058896999806166 | 108507 | 855 | 97664 | 0 | unknown | included via existing cell |
| [0038](../../results-raw/contrast-v2-20261102-stage1/0038) | regional_policy | codex | gpt-6.1-sol | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 16.210093999747187 | 47122 | 270 | 38656 | 0 | unknown | included |
| [0039/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0039/continuations/answer-01) | regional_policy | codex | gpt-6.1-sol | ruby-plainspoken | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 20.694253000430763 | 113509 | 908 | 106624 | 0 | unknown | included via existing cell |
| [0039](../../results-raw/contrast-v2-20261102-stage1/0039) | regional_policy | codex | gpt-6.1-sol | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 23.08675600029528 | 77907 | 362 | 72192 | 0 | unknown | included |
| [0040/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0040/continuations/answer-01) | regional_policy | codex | gpt-6.1-sol | ruby-plainspoken | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 13.783962999936193 | 118564 | 918 | 107904 | 0 | unknown | included via existing cell |
| [0040](../../results-raw/contrast-v2-20261102-stage1/0040) | regional_policy | codex | gpt-6.1-sol | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 19.04856299981475 | 78689 | 364 | 70528 | 0 | unknown | included |
| [0041/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0041/continuations/answer-01) | regional_policy | codex | gpt-6.1-sol | baseline | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 20.608566000126302 | 153085 | 997 | 135296 | 0 | unknown | included via existing cell |
| [0041](../../results-raw/contrast-v2-20261102-stage1/0041) | regional_policy | codex | gpt-6.1-sol | baseline | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 20.285808000247926 | 87567 | 401 | 77824 | 0 | unknown | included |
| [0042/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0042/continuations/answer-01) | regional_policy | codex | gpt-6.1-sol | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 26.095557999797165 | 274412 | 1269 | 240640 | 0 | unknown | included via existing cell |
| [0042](../../results-raw/contrast-v2-20261102-stage1/0042) | regional_policy | codex | gpt-6.1-sol | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 22.264983999542892 | 119533 | 430 | 97664 | 0 | unknown | included |
| [0043](../../results-raw/contrast-v2-20261102-stage1/0043) | regional_policy | codex | gpt-6.1-sol | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 29.65635299962014 | 80068 | 848 | 70912 | 0 | unknown | included |
| [0044](../../results-raw/contrast-v2-20261102-stage1/0044) | regional_policy | codex | gpt-6.1-sol | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 28.166297999676317 | 154501 | 1042 | 118400 | 0 | unknown | included |
| [0045](../../results-raw/contrast-v2-20261102-stage1/0045) | regional_policy | codex | gpt-6.1-sol | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 22.58554599992931 | 73917 | 664 | 68224 | 0 | unknown | included |
| [0046](../../results-raw/contrast-v2-20261102-stage1/0046) | regional_policy | codex | gpt-6.1-sol | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 26.216889000032097 | 79105 | 842 | 73472 | 0 | unknown | included |
| [0047](../../results-raw/contrast-v2-20261102-stage1/0047) | regional_policy | codex | gpt-6.1-sol | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 21.34693200001493 | 73980 | 676 | 67328 | 0 | unknown | included |
| [0048](../../results-raw/contrast-v2-20261102-stage1/0048) | regional_policy | codex | gpt-6.1-sol | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 27.102265999652445 | 155194 | 1041 | 137088 | 0 | unknown | included |
| [0049](../../results-raw/contrast-v2-20261102-stage1/0049) | archive_export | claude | claude-opus-5 | ruby-plainspoken | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 113.72396299988031 | 24 | 8116 | 316071 | 19220 | 0.5532555000000001 | included |

## Change counts

Counts come from `git diff` between the saved baseline and final bundles. Binary file changes count as files, but not text lines.

### [0001/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0001/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 37 | 1 |
| tests | 0 | 0 | 1 | 121 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0001](../../results-raw/contrast-v2-20261102-stage1/0001)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 22 | 0 |
| tests | 0 | 0 | 1 | 63 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0002/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0002/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 18 | 1 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0002](../../results-raw/contrast-v2-20261102-stage1/0002)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 18 | 1 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0003](../../results-raw/contrast-v2-20261102-stage1/0003)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 15 | 1 |
| tests | 0 | 0 | 1 | 73 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0004](../../results-raw/contrast-v2-20261102-stage1/0004)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 11 | 1 |
| tests | 0 | 0 | 1 | 28 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0005](../../results-raw/contrast-v2-20261102-stage1/0005)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 31 | 2 |
| tests | 1 | 0 | 0 | 56 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0006](../../results-raw/contrast-v2-20261102-stage1/0006)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 19 | 1 |
| tests | 1 | 0 | 0 | 73 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0007](../../results-raw/contrast-v2-20261102-stage1/0007)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 23 | 1 |
| tests | 0 | 0 | 1 | 37 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0008](../../results-raw/contrast-v2-20261102-stage1/0008)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 12 | 1 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0009](../../results-raw/contrast-v2-20261102-stage1/0009)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 11 | 1 |
| tests | 0 | 0 | 1 | 38 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0010](../../results-raw/contrast-v2-20261102-stage1/0010)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 1 | 0 | 0 | 44 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0011](../../results-raw/contrast-v2-20261102-stage1/0011)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 11 | 1 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0012](../../results-raw/contrast-v2-20261102-stage1/0012)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 15 | 1 |
| tests | 1 | 0 | 0 | 71 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0013/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0013/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 8 | 0 |
| tests | 0 | 0 | 1 | 44 | 2 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0013](../../results-raw/contrast-v2-20261102-stage1/0013)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0014](../../results-raw/contrast-v2-20261102-stage1/0014)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 0 |
| tests | 0 | 0 | 1 | 30 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0015](../../results-raw/contrast-v2-20261102-stage1/0015)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 12 | 0 |
| tests | 0 | 0 | 1 | 46 | 2 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0016](../../results-raw/contrast-v2-20261102-stage1/0016)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 8 | 0 |
| tests | 0 | 0 | 1 | 51 | 2 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0017](../../results-raw/contrast-v2-20261102-stage1/0017)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 8 | 0 |
| tests | 0 | 0 | 1 | 30 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0018/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0018/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 50 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0018](../../results-raw/contrast-v2-20261102-stage1/0018)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0019](../../results-raw/contrast-v2-20261102-stage1/0019)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 48 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0020](../../results-raw/contrast-v2-20261102-stage1/0020)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 32 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0021](../../results-raw/contrast-v2-20261102-stage1/0021)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 42 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0022](../../results-raw/contrast-v2-20261102-stage1/0022)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 51 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0023](../../results-raw/contrast-v2-20261102-stage1/0023)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 32 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0024](../../results-raw/contrast-v2-20261102-stage1/0024)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 10 | 1 |
| tests | 0 | 0 | 1 | 23 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0025/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0025/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 1 | 0 | 0 | 15 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0025/continuations/answer-02](../../results-raw/contrast-v2-20261102-stage1/0025/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 2 | 0 | 0 | 31 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0025](../../results-raw/contrast-v2-20261102-stage1/0025)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 1 | 0 | 0 | 15 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0026/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0026/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 15 | 4 |
| tests | 0 | 0 | 1 | 40 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0026](../../results-raw/contrast-v2-20261102-stage1/0026)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 14 | 4 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0027/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0027/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 29 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0027](../../results-raw/contrast-v2-20261102-stage1/0027)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0028/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0028/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 8 | 2 |
| tests | 0 | 0 | 1 | 61 | 5 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0028](../../results-raw/contrast-v2-20261102-stage1/0028)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 8 | 2 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0029/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0029/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 22 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0029](../../results-raw/contrast-v2-20261102-stage1/0029)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0030/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0030/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 27 | 4 |
| tests | 0 | 0 | 1 | 75 | 3 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0030](../../results-raw/contrast-v2-20261102-stage1/0030)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 25 | 4 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0031](../../results-raw/contrast-v2-20261102-stage1/0031)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 37 | 17 |
| tests | 0 | 0 | 1 | 17 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0032](../../results-raw/contrast-v2-20261102-stage1/0032)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 16 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0033](../../results-raw/contrast-v2-20261102-stage1/0033)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 8 | 3 |
| tests | 1 | 0 | 0 | 61 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0034](../../results-raw/contrast-v2-20261102-stage1/0034)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 14 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0035](../../results-raw/contrast-v2-20261102-stage1/0035)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 45 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0036](../../results-raw/contrast-v2-20261102-stage1/0036)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 28 | 14 |
| tests | 0 | 0 | 1 | 44 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0037/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0037/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 22 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0037](../../results-raw/contrast-v2-20261102-stage1/0037)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0038/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0038/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0038](../../results-raw/contrast-v2-20261102-stage1/0038)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0039/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0039/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0039](../../results-raw/contrast-v2-20261102-stage1/0039)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0040/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0040/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0040](../../results-raw/contrast-v2-20261102-stage1/0040)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0041/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0041/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 21 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0041](../../results-raw/contrast-v2-20261102-stage1/0041)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0042/continuations/answer-01](../../results-raw/contrast-v2-20261102-stage1/0042/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 23 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0042](../../results-raw/contrast-v2-20261102-stage1/0042)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0043](../../results-raw/contrast-v2-20261102-stage1/0043)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0044](../../results-raw/contrast-v2-20261102-stage1/0044)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0045](../../results-raw/contrast-v2-20261102-stage1/0045)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0046](../../results-raw/contrast-v2-20261102-stage1/0046)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0047](../../results-raw/contrast-v2-20261102-stage1/0047)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 18 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0048](../../results-raw/contrast-v2-20261102-stage1/0048)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 2 | 2 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0049](../../results-raw/contrast-v2-20261102-stage1/0049)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 14 | 4 |
| tests | 1 | 0 | 0 | 44 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

