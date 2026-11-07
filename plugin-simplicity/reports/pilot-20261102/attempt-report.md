# Trial comparison report

This is a diagnostic index of every recorded attempt. Fake-adapter rows are retained for auditability but excluded from research data. Counts describe changed files and text lines; they are not quality scores. No winner is selected and no statistical inference is made.
The attempts table is not the assigned-cell denominator. Actual continuation turns under a cell are part of that existing cell; the final continuation code and agent time are included in the cell comparison. Separate `continuation_smoke` audit tasks are excluded.

Token and cost values are reported only when present in aggregate usage events; a Codex field is summed only when every completed turn provides it. Missing values are `unknown`, never zero. Codex input tokens already include cached input; cache-read and cache-write counts are subsets, not additional input. Claude reports cache categories separately. Do not sum token categories across providers. Transcript contents and absolute workspace paths are not included.

## Attempts

| Trial path | Task | Agent | Model | Condition | Track | Status | Incident | Eligibility | Checks | Restored | Agent seconds | Input tokens | Output tokens | Cache read | Cache creation | Cost (USD) | Research data |
|---|---|---|---|---|---|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|
| [0001](../../results-raw/pilot-20261102/0001) | report | claude | claude-opus-5 | rubypowers | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 27.280377000104636 | 16 | 1770 | 197755 | 25549 | 0.3986975 | included |
| [0002](../../results-raw/pilot-20261102/0002) | report | claude | claude-opus-5 | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 36.62941400008276 | 14 | 1743 | 143104 | 14913 | 0.26432700000000003 | included |
| [0003](../../results-raw/pilot-20261102/0003) | report | claude | claude-opus-5 | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 30.791056000161916 | 14 | 2070 | 154147 | 18344 | 0.31233349999999993 | included |
| [0004](../../results-raw/pilot-20261102/0004) | report | claude | claude-opus-5 | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 33.23960199998692 | 14 | 2003 | 143603 | 15041 | 0.2723565 | included |
| [0005](../../results-raw/pilot-20261102/0005) | report | claude | claude-opus-5 | rubypowers | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 34.77192299999297 | 18 | 2255 | 256525 | 30080 | 0.48552750000000006 | included |
| [0006](../../results-raw/pilot-20261102/0006) | report | claude | claude-opus-5 | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 36.272065999917686 | 18 | 2462 | 204014 | 18636 | 0.35000699999999996 | included |
| [0007](../../results-raw/pilot-20261102/0007) | report | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 21.365234000142664 | 12 | 1543 | 121683 | 15045 | 0.2499265 | included |
| [0008](../../results-raw/pilot-20261102/0008) | report | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 24.64436999987811 | 14 | 1377 | 144236 | 15159 | 0.25820299999999996 | included |
| [0009](../../results-raw/pilot-20261102/0009) | report | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 33.81140000000596 | 14 | 2076 | 192469 | 29960 | 0.4478045 | included |
| [0010](../../results-raw/pilot-20261102/0010) | report | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 23.764702000189573 | 14 | 1640 | 143725 | 14980 | 0.26273250000000004 | included |
| [0011](../../results-raw/pilot-20261102/0011) | report | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 22.90458200033754 | 12 | 1711 | 142267 | 25596 | 0.36992850000000005 | included |
| [0012](../../results-raw/pilot-20261102/0012) | report | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 28.477431000210345 | 14 | 2104 | 154570 | 18442 | 0.314375 | included |
| [0013](../../results-raw/pilot-20261102/0013) | report | codex | gpt-5.6-terra | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 27.026723000220954 | 69322 | 743 | 56064 | 0 | unknown | included |
| [0014/continuations/answer-01](../../results-raw/pilot-20261102/0014/continuations/answer-01) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 24.691097000148147 | 149307 | 1566 | 130560 | 0 | unknown | included via existing cell |
| [0014/continuations/answer-02](../../results-raw/pilot-20261102/0014/continuations/answer-02) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 21.323293999768794 | 232758 | 2132 | 210688 | 0 | unknown | included via existing cell |
| [0014/continuations/answer-03](../../results-raw/pilot-20261102/0014/continuations/answer-03) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 38.09873900003731 | 397508 | 3731 | 365056 | 0 | unknown | included via existing cell |
| [0014/continuations/answer-04](../../results-raw/pilot-20261102/0014/continuations/answer-04) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 22.902435999829322 | 507852 | 4487 | 469760 | 0 | unknown | included via existing cell |
| [0014/continuations/answer-05](../../results-raw/pilot-20261102/0014/continuations/answer-05) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 112.60039300005883 | 1342215 | 7685 | 1285888 | 0 | unknown | included via existing cell |
| [0014/continuations/answer-06](../../results-raw/pilot-20261102/0014/continuations/answer-06) | report | codex | gpt-5.6-terra | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 50.03948999987915 | 1620676 | 9278 | 1558784 | 0 | unknown | included via existing cell |
| [0014](../../results-raw/pilot-20261102/0014) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 30.923345000017434 | 95462 | 763 | 78848 | 0 | unknown | included |
| [0015](../../results-raw/pilot-20261102/0015) | report | codex | gpt-5.6-terra | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 23.062855000142008 | 95499 | 1027 | 86528 | 0 | unknown | included |
| [0016/continuations/answer-01](../../results-raw/pilot-20261102/0016/continuations/answer-01) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 14.226624999660999 | 147468 | 1253 | 128512 | 0 | unknown | included via existing cell |
| [0016/continuations/answer-02](../../results-raw/pilot-20261102/0016/continuations/answer-02) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 15.601104999892414 | 257307 | 2158 | 235008 | 0 | unknown | included via existing cell |
| [0016/continuations/answer-03](../../results-raw/pilot-20261102/0016/continuations/answer-03) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 22.44461499992758 | 376531 | 3743 | 349696 | 0 | unknown | included via existing cell |
| [0016/continuations/answer-04](../../results-raw/pilot-20261102/0016/continuations/answer-04) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 17.77662399969995 | 507622 | 4655 | 475648 | 0 | unknown | included via existing cell |
| [0016/continuations/answer-05](../../results-raw/pilot-20261102/0016/continuations/answer-05) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 37.59584699990228 | 1086236 | 7109 | 1039872 | 0 | unknown | included via existing cell |
| [0016/continuations/answer-06](../../results-raw/pilot-20261102/0016/continuations/answer-06) | report | codex | gpt-5.6-terra | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 27.158272000029683 | 1327711 | 8882 | 1275904 | 0 | unknown | included via existing cell |
| [0016](../../results-raw/pilot-20261102/0016) | report | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 17.982446999754757 | 94574 | 699 | 77824 | 0 | unknown | included |
| [0017](../../results-raw/pilot-20261102/0017) | report | codex | gpt-5.6-terra | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 25.365536999888718 | 112518 | 1377 | 102656 | 0 | unknown | included |
| [0018](../../results-raw/pilot-20261102/0018) | report | codex | gpt-5.6-terra | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 24.598163000307977 | 84764 | 1397 | 66304 | 0 | unknown | included |
| [0019](../../results-raw/pilot-20261102/0019) | report | codex | gpt-5.6-terra | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 26.606013999786228 | 69550 | 729 | 64256 | 0 | unknown | included |
| [0020](../../results-raw/pilot-20261102/0020) | report | codex | gpt-5.6-terra | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 64.24313100008294 | 296654 | 1982 | 272640 | 0 | unknown | included |
| [0021](../../results-raw/pilot-20261102/0021) | report | codex | gpt-5.6-terra | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 33.43580299988389 | 77245 | 1006 | 66304 | 0 | unknown | included |
| [0022](../../results-raw/pilot-20261102/0022) | report | codex | gpt-5.6-terra | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 16.9804570004344 | 83822 | 823 | 77312 | 0 | unknown | included |
| [0023/continuations/answer-01](../../results-raw/pilot-20261102/0023/continuations/answer-01) | report | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 16.435283000115305 | 244196 | 1978 | 220928 | 0 | unknown | included via existing cell |
| [0023/continuations/answer-02](../../results-raw/pilot-20261102/0023/continuations/answer-02) | report | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 20.982889000326395 | 368885 | 3346 | 339712 | 0 | unknown | included via existing cell |
| [0023/continuations/answer-03](../../results-raw/pilot-20261102/0023/continuations/answer-03) | report | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 16.556871000211686 | 515084 | 4064 | 475904 | 0 | unknown | included via existing cell |
| [0023/continuations/answer-04](../../results-raw/pilot-20261102/0023/continuations/answer-04) | report | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 117.31998899998143 | 1174960 | 7713 | 1118976 | 0 | unknown | included via existing cell |
| [0023/continuations/answer-05](../../results-raw/pilot-20261102/0023/continuations/answer-05) | report | codex | gpt-5.6-terra | rubypowers | specified | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 24.949837000109255 | 1311705 | 9075 | 1251328 | 0 | unknown | included via existing cell |
| [0023](../../results-raw/pilot-20261102/0023) | report | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 19.42625299980864 | 100093 | 976 | 81920 | 0 | unknown | included |
| [0024](../../results-raw/pilot-20261102/0024) | report | codex | gpt-5.6-terra | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 44.597212000284344 | 95879 | 1153 | 84480 | 0 | unknown | included |
| [0025](../../results-raw/pilot-20261102/0025) | csv_import | claude | claude-opus-5 | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 71.26170299993828 | 18 | 4468 | 217309 | 21135 | 0.4317945 | included |
| [0026](../../results-raw/pilot-20261102/0026) | csv_import | claude | claude-opus-5 | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 37.16803500009701 | 12 | 2920 | 124142 | 16224 | 0.297371 | included |
| [0027](../../results-raw/pilot-20261102/0027) | csv_import | claude | claude-opus-5 | rubypowers | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 79.82002199999988 | 20 | 5056 | 277107 | 29756 | 0.5626135 | included |
| [0028](../../results-raw/pilot-20261102/0028) | csv_import | claude | claude-opus-5 | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 62.93728099996224 | 18 | 3999 | 222628 | 20680 | 0.41817899999999997 | included |
| [0029](../../results-raw/pilot-20261102/0029) | csv_import | claude | claude-opus-5 | rubypowers | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 77.18304299982265 | 20 | 4632 | 272015 | 29035 | 0.5422575000000001 | included |
| [0030](../../results-raw/pilot-20261102/0030) | csv_import | claude | claude-opus-5 | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 54.63818700006232 | 18 | 4004 | 204574 | 18224 | 0.384717 | included |
| [0031](../../results-raw/pilot-20261102/0031) | csv_import | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 49.08479300001636 | 18 | 3809 | 203038 | 17888 | 0.375714 | included |
| [0032](../../results-raw/pilot-20261102/0032) | csv_import | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 50.36570299975574 | 16 | 3930 | 231492 | 32026 | 0.534336 | included |
| [0033](../../results-raw/pilot-20261102/0033) | csv_import | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 46.75313000008464 | 16 | 3738 | 175929 | 17606 | 0.35755450000000005 | included |
| [0034](../../results-raw/pilot-20261102/0034) | csv_import | claude | claude-opus-5 | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 50.951828999910504 | 18 | 4061 | 203514 | 18022 | 0.38359200000000004 | included |
| [0035](../../results-raw/pilot-20261102/0035) | csv_import | claude | claude-opus-5 | rubypowers | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 49.90825199987739 | 18 | 4010 | 269753 | 32568 | 0.5608965000000001 | included |
| [0036](../../results-raw/pilot-20261102/0036) | csv_import | claude | claude-opus-5 | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 64.87267399998382 | 20 | 4889 | 244672 | 21797 | 0.462631 | included |
| [0037/continuations/answer-01](../../results-raw/pilot-20261102/0037/continuations/answer-01) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 27.698236000258476 | 212357 | 1448 | 190464 | 0 | unknown | included via existing cell |
| [0037/continuations/answer-02](../../results-raw/pilot-20261102/0037/continuations/answer-02) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 23.481250000186265 | 329970 | 2167 | 304128 | 0 | unknown | included via existing cell |
| [0037/continuations/answer-03](../../results-raw/pilot-20261102/0037/continuations/answer-03) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 60.23501399997622 | 528259 | 4638 | 493056 | 0 | unknown | included via existing cell |
| [0037/continuations/answer-04](../../results-raw/pilot-20261102/0037/continuations/answer-04) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 17.931257000193 | 639434 | 5164 | 598784 | 0 | unknown | included via existing cell |
| [0037/continuations/answer-05](../../results-raw/pilot-20261102/0037/continuations/answer-05) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 107.24584100022912 | 1340638 | 9264 | 1282560 | 0 | unknown | included via existing cell |
| [0037/continuations/answer-06](../../results-raw/pilot-20261102/0037/continuations/answer-06) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 30.23798600025475 | 1480616 | 9901 | 1420032 | 0 | unknown | included via existing cell |
| [0037](../../results-raw/pilot-20261102/0037) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 31.7364459997043 | 127113 | 738 | 108288 | 0 | unknown | included |
| [0038](../../results-raw/pilot-20261102/0038) | csv_import | codex | gpt-5.6-terra | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 40.72469499986619 | 80122 | 1240 | 69376 | 0 | unknown | included |
| [0039](../../results-raw/pilot-20261102/0039) | csv_import | codex | gpt-5.6-terra | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 35.62305400008336 | 71286 | 984 | 65280 | 0 | unknown | included |
| [0040](../../results-raw/pilot-20261102/0040) | csv_import | codex | gpt-5.6-terra | baseline | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 21.490996999666095 | 86580 | 1202 | 79360 | 0 | unknown | included |
| [0041](../../results-raw/pilot-20261102/0041) | csv_import | codex | gpt-5.6-terra | ruby-plainspoken | natural | complete | unknown | behavioral attempt | 2/2 passed | true | 44.841066000051796 | 80241 | 1314 | 71424 | 0 | unknown | included |
| [0042/continuations/answer-01](../../results-raw/pilot-20261102/0042/continuations/answer-01) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 16.040171999949962 | 167950 | 1678 | 148736 | 0 | unknown | included via existing cell |
| [0042/continuations/answer-02](../../results-raw/pilot-20261102/0042/continuations/answer-02) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 11.351313999854028 | 251531 | 2169 | 229888 | 0 | unknown | included via existing cell |
| [0042/continuations/answer-03](../../results-raw/pilot-20261102/0042/continuations/answer-03) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 23.774937000125647 | 402626 | 4169 | 374016 | 0 | unknown | included via existing cell |
| [0042/continuations/answer-04](../../results-raw/pilot-20261102/0042/continuations/answer-04) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 14.751206000335515 | 545687 | 4825 | 508160 | 0 | unknown | included via existing cell |
| [0042/continuations/answer-05/infrastructure-recovery](../../results-raw/pilot-20261102/0042/continuations/answer-05/infrastructure-recovery) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | timeout | unknown | part of existing cell (continuation; not an additional trial) | unknown | false | 816.0206299996935 | 2029390 | 8999 | 1963520 | 0 | unknown | included via existing cell |
| [0042/continuations/answer-05](../../results-raw/pilot-20261102/0042/continuations/answer-05) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | timeout | unknown | part of existing cell (continuation; not an additional trial) | unknown | true | 816.0206299996935 | 2029390 | 8999 | 1963520 | 0 | unknown | included via existing cell |
| [0042](../../results-raw/pilot-20261102/0042) | csv_import | codex | gpt-5.6-terra | rubypowers | natural | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 17.14999599987641 | 86919 | 816 | 70656 | 0 | unknown | included |
| [0043](../../results-raw/pilot-20261102/0043) | csv_import | codex | gpt-5.6-terra | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 46.82450299989432 | 71218 | 1348 | 64256 | 0 | unknown | included |
| [0044](../../results-raw/pilot-20261102/0044) | csv_import | codex | gpt-5.6-terra | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 22.047240999992937 | 81193 | 1421 | 68352 | 0 | unknown | included |
| [0045/continuations/answer-01](../../results-raw/pilot-20261102/0045/continuations/answer-01) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 21.668779000174254 | 126234 | 1330 | 112384 | 0 | unknown | included via existing cell |
| [0045/continuations/answer-02](../../results-raw/pilot-20261102/0045/continuations/answer-02) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 25.9394499999471 | 211583 | 2100 | 195584 | 0 | unknown | included via existing cell |
| [0045/continuations/answer-03](../../results-raw/pilot-20261102/0045/continuations/answer-03) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 59.89518899982795 | 335503 | 4103 | 313344 | 0 | unknown | included via existing cell |
| [0045/continuations/answer-04](../../results-raw/pilot-20261102/0045/continuations/answer-04) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 28.165141000412405 | 442547 | 4836 | 412928 | 0 | unknown | included via existing cell |
| [0045/continuations/answer-05](../../results-raw/pilot-20261102/0045/continuations/answer-05) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 304.572266000323 | 1259088 | 8307 | 1208576 | 0 | unknown | included via existing cell |
| [0045/continuations/answer-06](../../results-raw/pilot-20261102/0045/continuations/answer-06) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 22.720035000238568 | 1393616 | 8863 | 1340928 | 0 | unknown | included via existing cell |
| [0045](../../results-raw/pilot-20261102/0045) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 29.12696100026369 | 71057 | 748 | 59648 | 0 | unknown | included |
| [0046](../../results-raw/pilot-20261102/0046) | csv_import | codex | gpt-5.6-terra | baseline | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 36.1674790000543 | 71158 | 1302 | 64256 | 0 | unknown | included |
| [0047/continuations/answer-01](../../results-raw/pilot-20261102/0047/continuations/answer-01) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 30.952889000065625 | 213213 | 1578 | 191488 | 0 | unknown | included via existing cell |
| [0047/continuations/answer-02](../../results-raw/pilot-20261102/0047/continuations/answer-02) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 26.455628000199795 | 303019 | 2270 | 277760 | 0 | unknown | included via existing cell |
| [0047/continuations/answer-03](../../results-raw/pilot-20261102/0047/continuations/answer-03) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 71.59614500030875 | 538974 | 5009 | 502272 | 0 | unknown | included via existing cell |
| [0047/continuations/answer-04](../../results-raw/pilot-20261102/0047/continuations/answer-04) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 19.44753299979493 | 656864 | 5498 | 612096 | 0 | unknown | included via existing cell |
| [0047/continuations/answer-05](../../results-raw/pilot-20261102/0047/continuations/answer-05) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | part of existing cell (continuation; not an additional trial) | 1/2 passed | true | 459.1573269995861 | 1606089 | 8933 | 1541632 | 0 | unknown | included via existing cell |
| [0047/continuations/answer-06](../../results-raw/pilot-20261102/0047/continuations/answer-06) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | complete | unknown | part of existing cell (continuation; not an additional trial) | 2/2 passed | true | 21.51890500029549 | 1753929 | 9506 | 1686272 | 0 | unknown | included via existing cell |
| [0047](../../results-raw/pilot-20261102/0047) | csv_import | codex | gpt-5.6-terra | rubypowers | specified | awaiting_review | unknown | behavioral attempt | 1/2 passed | true | 38.62421299982816 | 97585 | 816 | 78848 | 0 | unknown | included |
| [0048](../../results-raw/pilot-20261102/0048) | csv_import | codex | gpt-5.6-terra | ruby-plainspoken | specified | complete | unknown | behavioral attempt | 2/2 passed | true | 51.08384699979797 | 116937 | 1733 | 105728 | 0 | unknown | included |

## Change counts

Counts come from `git diff` between the saved baseline and final bundles. Binary file changes count as files, but not text lines.

### [0001](../../results-raw/pilot-20261102/0001)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 21 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0002](../../results-raw/pilot-20261102/0002)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 21 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0003](../../results-raw/pilot-20261102/0003)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 6 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0004](../../results-raw/pilot-20261102/0004)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 22 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0005](../../results-raw/pilot-20261102/0005)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 21 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0006](../../results-raw/pilot-20261102/0006)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0007](../../results-raw/pilot-20261102/0007)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 15 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0008](../../results-raw/pilot-20261102/0008)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 15 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0009](../../results-raw/pilot-20261102/0009)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0010](../../results-raw/pilot-20261102/0010)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0011](../../results-raw/pilot-20261102/0011)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 24 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0012](../../results-raw/pilot-20261102/0012)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 3 | 2 |
| tests | 0 | 0 | 1 | 15 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0013](../../results-raw/pilot-20261102/0013)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0014/continuations/answer-01](../../results-raw/pilot-20261102/0014/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 19 | 0 |

### [0014/continuations/answer-02](../../results-raw/pilot-20261102/0014/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 17 | 0 |

### [0014/continuations/answer-03](../../results-raw/pilot-20261102/0014/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 87 | 0 |

### [0014/continuations/answer-04](../../results-raw/pilot-20261102/0014/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 87 | 0 |

### [0014/continuations/answer-05](../../results-raw/pilot-20261102/0014/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 13 | 0 |
| tests | 2 | 0 | 0 | 50 | 0 |
| docs | 3 | 0 | 0 | 104 | 0 |

### [0014/continuations/answer-06](../../results-raw/pilot-20261102/0014/continuations/answer-06)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 1 | 0 | 1 | 5 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 2 | 0 | 0 | 87 | 0 |

### [0014](../../results-raw/pilot-20261102/0014)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0015](../../results-raw/pilot-20261102/0015)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0016/continuations/answer-01](../../results-raw/pilot-20261102/0016/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 9 | 0 |

### [0016/continuations/answer-02](../../results-raw/pilot-20261102/0016/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 27 | 0 |

### [0016/continuations/answer-03](../../results-raw/pilot-20261102/0016/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 114 | 0 |

### [0016/continuations/answer-04](../../results-raw/pilot-20261102/0016/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 114 | 0 |

### [0016/continuations/answer-05](../../results-raw/pilot-20261102/0016/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 13 | 0 |
| tests | 2 | 0 | 0 | 65 | 0 |
| docs | 3 | 0 | 0 | 141 | 0 |

### [0016/continuations/answer-06](../../results-raw/pilot-20261102/0016/continuations/answer-06)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 1 | 0 | 1 | 5 | 2 |
| tests | 0 | 0 | 1 | 25 | 0 |
| docs | 2 | 0 | 0 | 114 | 0 |

### [0016](../../results-raw/pilot-20261102/0016)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0017](../../results-raw/pilot-20261102/0017)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0018](../../results-raw/pilot-20261102/0018)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 5 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0019](../../results-raw/pilot-20261102/0019)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 11 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0020](../../results-raw/pilot-20261102/0020)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 17 | 2 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0021](../../results-raw/pilot-20261102/0021)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 17 | 2 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0022](../../results-raw/pilot-20261102/0022)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 12 | 1 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0023/continuations/answer-01](../../results-raw/pilot-20261102/0023/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 29 | 0 |

### [0023/continuations/answer-02](../../results-raw/pilot-20261102/0023/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 108 | 0 |

### [0023/continuations/answer-03](../../results-raw/pilot-20261102/0023/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 108 | 0 |

### [0023/continuations/answer-04](../../results-raw/pilot-20261102/0023/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 12 | 0 |
| tests | 2 | 0 | 0 | 50 | 0 |
| docs | 3 | 0 | 0 | 137 | 0 |

### [0023/continuations/answer-05](../../results-raw/pilot-20261102/0023/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 1 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 10 | 0 |
| docs | 2 | 0 | 0 | 108 | 0 |

### [0023](../../results-raw/pilot-20261102/0023)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0024](../../results-raw/pilot-20261102/0024)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 2 |
| tests | 0 | 0 | 1 | 17 | 2 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0025](../../results-raw/pilot-20261102/0025)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 16 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0026](../../results-raw/pilot-20261102/0026)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 22 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0027](../../results-raw/pilot-20261102/0027)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 5 |
| tests | 0 | 0 | 1 | 46 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0028](../../results-raw/pilot-20261102/0028)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 14 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0029](../../results-raw/pilot-20261102/0029)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 9 | 8 |
| tests | 0 | 0 | 1 | 26 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0030](../../results-raw/pilot-20261102/0030)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 5 |
| tests | 0 | 0 | 1 | 27 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0031](../../results-raw/pilot-20261102/0031)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 5 | 6 |
| tests | 0 | 0 | 1 | 59 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0032](../../results-raw/pilot-20261102/0032)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 12 | 8 |
| tests | 0 | 0 | 1 | 58 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0033](../../results-raw/pilot-20261102/0033)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 5 |
| tests | 0 | 0 | 1 | 65 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0034](../../results-raw/pilot-20261102/0034)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 7 | 6 |
| tests | 0 | 0 | 1 | 74 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0035](../../results-raw/pilot-20261102/0035)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 9 | 7 |
| tests | 0 | 0 | 1 | 61 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0036](../../results-raw/pilot-20261102/0036)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 7 | 6 |
| tests | 0 | 0 | 1 | 48 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0037/continuations/answer-01](../../results-raw/pilot-20261102/0037/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 13 | 0 |

### [0037/continuations/answer-02](../../results-raw/pilot-20261102/0037/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 27 | 0 |

### [0037/continuations/answer-03](../../results-raw/pilot-20261102/0037/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 163 | 0 |

### [0037/continuations/answer-04](../../results-raw/pilot-20261102/0037/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 163 | 0 |

### [0037/continuations/answer-05](../../results-raw/pilot-20261102/0037/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 31 | 0 |
| tests | 2 | 0 | 0 | 64 | 0 |
| docs | 4 | 0 | 0 | 326 | 0 |

### [0037/continuations/answer-06](../../results-raw/pilot-20261102/0037/continuations/answer-06)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 1 | 0 | 1 | 8 | 6 |
| tests | 0 | 0 | 1 | 22 | 0 |
| docs | 2 | 0 | 0 | 163 | 0 |

### [0037](../../results-raw/pilot-20261102/0037)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0038](../../results-raw/pilot-20261102/0038)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 5 | 4 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0039](../../results-raw/pilot-20261102/0039)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0040](../../results-raw/pilot-20261102/0040)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0041](../../results-raw/pilot-20261102/0041)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 4 | 5 |
| tests | 0 | 0 | 1 | 20 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0042/continuations/answer-01](../../results-raw/pilot-20261102/0042/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 22 | 0 |

### [0042/continuations/answer-02](../../results-raw/pilot-20261102/0042/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 20 | 0 |

### [0042/continuations/answer-03](../../results-raw/pilot-20261102/0042/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 149 | 0 |

### [0042/continuations/answer-04](../../results-raw/pilot-20261102/0042/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 149 | 0 |

### [0042/continuations/answer-05/infrastructure-recovery](../../results-raw/pilot-20261102/0042/continuations/answer-05/infrastructure-recovery)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | unknown | unknown | unknown | unknown | unknown |
| tests | unknown | unknown | unknown | unknown | unknown |
| docs | unknown | unknown | unknown | unknown | unknown |

Change counts unavailable: snapshot missing

### [0042/continuations/answer-05](../../results-raw/pilot-20261102/0042/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 31 | 0 |
| tests | 2 | 0 | 0 | 65 | 0 |
| docs | 3 | 0 | 0 | 169 | 0 |

### [0042](../../results-raw/pilot-20261102/0042)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0043](../../results-raw/pilot-20261102/0043)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 50 | 3 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0044](../../results-raw/pilot-20261102/0044)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 46 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0045/continuations/answer-01](../../results-raw/pilot-20261102/0045/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 16 | 0 |

### [0045/continuations/answer-02](../../results-raw/pilot-20261102/0045/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 40 | 0 |

### [0045/continuations/answer-03](../../results-raw/pilot-20261102/0045/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 146 | 0 |

### [0045/continuations/answer-04](../../results-raw/pilot-20261102/0045/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 146 | 0 |

### [0045/continuations/answer-05](../../results-raw/pilot-20261102/0045/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 30 | 0 |
| tests | 2 | 0 | 0 | 101 | 0 |
| docs | 4 | 0 | 0 | 292 | 0 |

### [0045/continuations/answer-06](../../results-raw/pilot-20261102/0045/continuations/answer-06)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 1 | 0 | 1 | 5 | 4 |
| tests | 0 | 0 | 1 | 62 | 3 |
| docs | 2 | 0 | 0 | 146 | 0 |

### [0045](../../results-raw/pilot-20261102/0045)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0046](../../results-raw/pilot-20261102/0046)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 40 | 3 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0047/continuations/answer-01](../../results-raw/pilot-20261102/0047/continuations/answer-01)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 11 | 0 |

### [0047/continuations/answer-02](../../results-raw/pilot-20261102/0047/continuations/answer-02)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 1 | 0 | 0 | 19 | 0 |

### [0047/continuations/answer-03](../../results-raw/pilot-20261102/0047/continuations/answer-03)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 135 | 0 |

### [0047/continuations/answer-04](../../results-raw/pilot-20261102/0047/continuations/answer-04)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 0 | 0 | 135 | 0 |

### [0047/continuations/answer-05](../../results-raw/pilot-20261102/0047/continuations/answer-05)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 3 | 0 | 0 | 30 | 0 |
| tests | 2 | 0 | 0 | 85 | 0 |
| docs | 4 | 0 | 0 | 270 | 0 |

### [0047/continuations/answer-06](../../results-raw/pilot-20261102/0047/continuations/answer-06)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 1 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 43 | 0 |
| docs | 2 | 0 | 0 | 135 | 0 |

### [0047](../../results-raw/pilot-20261102/0047)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 0 | 0 | 0 |
| tests | 0 | 0 | 0 | 0 | 0 |
| docs | 0 | 0 | 0 | 0 | 0 |

### [0048](../../results-raw/pilot-20261102/0048)

| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |
|---|---:|---:|---:|---:|---:|
| production | 0 | 0 | 1 | 6 | 5 |
| tests | 0 | 0 | 1 | 34 | 3 |
| docs | 0 | 0 | 0 | 0 | 0 |

