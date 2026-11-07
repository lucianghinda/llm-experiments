# Automated secondary review summary

Automated review is a secondary view, not primary human truth. Score disagreements are preserved without adjudication. Correctness concerns are reviewer questions or uncovered-edge-case notes, not newly failed acceptance checks.

Dimension scores are reported separately. No combined score, rank, or winner is produced. Correctness concerns below are reviewer questions or uncovered-edge-case notes, not failed acceptance checks.

## report: complete

Expected packets: 24; reviewers received: luna, terra.
- luna ratings: [source JSON](../automated-review/report-luna.json)
- terra ratings: [source JSON](../automated-review/report-terra.json)
- Packet mapping: [private key](../review-report/private-key.json)

### Dimension agreement

| Dimension | Paired packets | Exact agreement | Mean absolute disagreement |
|---|---:|---:|---:|
| concepts | 24 | 23 | 0.08333333333333333 |
| boundaries | 24 | 24 | 0.0 |
| cohesion | 24 | 23 | 0.041666666666666664 |
| interfaces | 24 | 24 | 0.0 |

### Per-packet ratings and evidence

#### R-0001: report / claude / specified / rubypowers

Packet: [R-0001.md](../review-report/packets/R-0001.md); cell: [open](../../../results-raw/pilot-20261102/0011); workspace: [open](../../../results-raw/pilot-20261102/0011/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0002: report / codex / specified / ruby-plainspoken

Packet: [R-0002.md](../review-report/packets/R-0002.md); cell: [open](../../../results-raw/pilot-20261102/0021); workspace: [open](../../../results-raw/pilot-20261102/0021/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0003: report / codex / natural / ruby-plainspoken

Packet: [R-0003.md](../review-report/packets/R-0003.md); cell: [open](../../../results-raw/pilot-20261102/0017); workspace: [open](../../../results-raw/pilot-20261102/0017/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0004: report / claude / natural / ruby-plainspoken

Packet: [R-0004.md](../review-report/packets/R-0004.md); cell: [open](../../../results-raw/pilot-20261102/0003); workspace: [open](../../../results-raw/pilot-20261102/0003/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0005: report / claude / specified / ruby-plainspoken

Packet: [R-0005.md](../review-report/packets/R-0005.md); cell: [open](../../../results-raw/pilot-20261102/0008); workspace: [open](../../../results-raw/pilot-20261102/0008/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0006: report / claude / specified / rubypowers

Packet: [R-0006.md](../review-report/packets/R-0006.md); cell: [open](../../../results-raw/pilot-20261102/0009); workspace: [open](../../../results-raw/pilot-20261102/0009/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0007: report / claude / natural / rubypowers

Packet: [R-0007.md](../review-report/packets/R-0007.md); cell: [open](../../../results-raw/pilot-20261102/0001); workspace: [open](../../../results-raw/pilot-20261102/0001/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0008: report / codex / natural / ruby-plainspoken

Packet: [R-0008.md](../review-report/packets/R-0008.md); cell: [open](../../../results-raw/pilot-20261102/0015); workspace: [open](../../../results-raw/pilot-20261102/0015/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0009: report / codex / natural / baseline

Packet: [R-0009.md](../review-report/packets/R-0009.md); cell: [open](../../../results-raw/pilot-20261102/0013); workspace: [open](../../../results-raw/pilot-20261102/0013/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0010: report / codex / natural / rubypowers

Packet: [R-0010.md](../review-report/packets/R-0010.md); cell: [open](../../../results-raw/pilot-20261102/0016); workspace: unknown; [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 4 | 4 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order.fetch(:status) == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: The optional status keyword and hash result are clear, but fetch(:status) makes a missing status field raise during filtering.
- Review questions / uncovered edge cases: When filtering, fetch(:status) raises KeyError for an order without that key, rather than treating it as a non-match.

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order.fetch(:status) raises for an absent status key during filtering and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: A filtered report raises KeyError for an order lacking :status; the contract does not specify that every order must have this key, so such an order cannot simply be excluded.

#### R-0011: report / codex / specified / rubypowers

Packet: [R-0011.md](../review-report/packets/R-0011.md); cell: [open](../../../results-raw/pilot-20261102/0023); workspace: unknown; [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0012: report / codex / natural / baseline

Packet: [R-0012.md](../review-report/packets/R-0012.md); cell: [open](../../../results-raw/pilot-20261102/0018); workspace: [open](../../../results-raw/pilot-20261102/0018/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 2 | 4 | -2 |
| boundaries | 4 | 4 | 0 |
| cohesion | 4 | 5 | -1 |
| interfaces | 2 | 2 | 0 |

**Luna evidence**

- concepts: summary accepts both a positional status and **options, then resolves them with options.fetch; this adds compatibility logic beyond the requested optional status.
- boundaries: The selection and aggregation remain in summary; there are no extracted layers or unjustified object boundaries.
- cohesion: Filtering and computing count/total remain together in OrderReport#summary, consistent with the baseline responsibility.
- interfaces: The parameter accepts positional or keyword status, but arbitrary keywords are silently accepted and ignored unless :status is present.
- Review questions / uncovered edge cases: Unknown keyword options are silently ignored, which can mask caller mistakes.

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection; the positional argument and options precedence introduce an extra input mechanism.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input; options.fetch adds a precedence rule without a stated need.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status = nil, **options) accepts positional status and arbitrary keywords, with :status overriding the positional value; unknown keywords are silently ignored; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: Unknown keywords are silently accepted and ignored; a misspelled status keyword returns an unfiltered report.

#### R-0013: report / codex / specified / baseline

Packet: [R-0013.md](../review-report/packets/R-0013.md); cell: [open](../../../results-raw/pilot-20261102/0019); workspace: [open](../../../results-raw/pilot-20261102/0019/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 4 | 4 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order.fetch(:status) == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: The optional status keyword and hash result are clear, but fetch(:status) makes a missing status field raise during filtering.
- Review questions / uncovered edge cases: When filtering, fetch(:status) raises KeyError for an order without that key, rather than treating it as a non-match.

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order.fetch(:status) raises for an absent status key during filtering and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: A filtered report raises KeyError for an order lacking :status; the contract does not specify that every order must have this key, so such an order cannot simply be excluded.

#### R-0014: report / claude / specified / baseline

Packet: [R-0014.md](../review-report/packets/R-0014.md); cell: [open](../../../results-raw/pilot-20261102/0010); workspace: [open](../../../results-raw/pilot-20261102/0010/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0015: report / claude / natural / rubypowers

Packet: [R-0015.md](../review-report/packets/R-0015.md); cell: [open](../../../results-raw/pilot-20261102/0005); workspace: [open](../../../results-raw/pilot-20261102/0005/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0016: report / claude / specified / ruby-plainspoken

Packet: [R-0016.md](../review-report/packets/R-0016.md); cell: [open](../../../results-raw/pilot-20261102/0012); workspace: [open](../../../results-raw/pilot-20261102/0012/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0017: report / claude / natural / baseline

Packet: [R-0017.md](../review-report/packets/R-0017.md); cell: [open](../../../results-raw/pilot-20261102/0002); workspace: [open](../../../results-raw/pilot-20261102/0002/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order.fetch(:status, nil) == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order.fetch(:status, nil) supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0018: report / codex / specified / baseline

Packet: [R-0018.md](../review-report/packets/R-0018.md); cell: [open](../../../results-raw/pilot-20261102/0022); workspace: [open](../../../results-raw/pilot-20261102/0022/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0019: report / codex / specified / ruby-plainspoken

Packet: [R-0019.md](../review-report/packets/R-0019.md); cell: [open](../../../results-raw/pilot-20261102/0024); workspace: [open](../../../results-raw/pilot-20261102/0024/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0020: report / claude / natural / baseline

Packet: [R-0020.md](../review-report/packets/R-0020.md); cell: [open](../../../results-raw/pilot-20261102/0004); workspace: [open](../../../results-raw/pilot-20261102/0004/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0021: report / claude / natural / ruby-plainspoken

Packet: [R-0021.md](../review-report/packets/R-0021.md); cell: [open](../../../results-raw/pilot-20261102/0006); workspace: [open](../../../results-raw/pilot-20261102/0006/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0022: report / codex / specified / rubypowers

Packet: [R-0022.md](../review-report/packets/R-0022.md); cell: [open](../../../results-raw/pilot-20261102/0020); workspace: [open](../../../results-raw/pilot-20261102/0020/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0023: report / claude / specified / baseline

Packet: [R-0023.md](../review-report/packets/R-0023.md); cell: [open](../../../results-raw/pilot-20261102/0007); workspace: [open](../../../results-raw/pilot-20261102/0007/workspace); [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 5 | 5 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order[:status] == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: summary exposes status as an optional keyword and keeps the existing {count:, total:} result; nil preserves the unfiltered path.
- Review questions / uncovered edge cases: none recorded

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order[:status] supplies the comparison value and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: none recorded

#### R-0024: report / codex / natural / rubypowers

Packet: [R-0024.md](../review-report/packets/R-0024.md); cell: [open](../../../results-raw/pilot-20261102/0014); workspace: unknown; [source index](../code-index.md).

| Dimension | Luna | Terra | Luna − Terra |
|---|---:|---:|---:|
| concepts | 5 | 5 | 0 |
| boundaries | 5 | 5 | 0 |
| cohesion | 5 | 5 | 0 |
| interfaces | 4 | 4 | 0 |

**Luna evidence**

- concepts: summary derives a local orders collection from the optional status and uses it for both count and total (status.nil? ? @orders : @orders.select { \|order\| order.fetch(:status) == status }).
- boundaries: The change stays within OrderReport#summary; the filtering operation is directly tied to the summary contract and needs no separate layer.
- cohesion: Status selection and the existing count/total aggregation remain in the report method that owns this behavior.
- interfaces: The optional status keyword and hash result are clear, but fetch(:status) makes a missing status field raise during filtering.
- Review questions / uncovered edge cases: When filtering, fetch(:status) raises KeyError for an order without that key, rather than treating it as a non-match.

**Terra evidence**

- concepts: The nil check selects either @orders or a status-matching collection; count and sum then share that collection.
- boundaries: Selection and aggregation stay in OrderReport#summary, and the local orders variable gives both aggregates the same input.
- cohesion: Status selection lives beside the existing count and total aggregation and retains the original fetch(:total) behavior.
- interfaces: summary(status: nil) exposes the requested keyword and returns count and total; order.fetch(:status) raises for an absent status key during filtering and fetch(:total) raises for a missing total.
- Review questions / uncovered edge cases: A filtered report raises KeyError for an order lacking :status; the contract does not specify that every order must have this key, so such an order cannot simply be excluded.

### Per-cell group medians

#### report / claude / natural / baseline (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / claude / natural / ruby-plainspoken (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / claude / natural / rubypowers (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / claude / specified / baseline (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / claude / specified / ruby-plainspoken (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / claude / specified / rubypowers (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / codex / natural / baseline (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 3.5 (n=2) | 4.5 (n=2) | 4.5 (n=2) | 3.5 (n=2) |
| Terra | 4.5 (n=2) | 4.5 (n=2) | 5.0 (n=2) | 3.5 (n=2) |

#### report / codex / natural / ruby-plainspoken (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / codex / natural / rubypowers (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 4.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 4.0 (n=2) |

#### report / codex / specified / baseline (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 4.5 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 4.5 (n=2) |

#### report / codex / specified / ruby-plainspoken (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

#### report / codex / specified / rubypowers (n=2)

| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |
|---|---:|---:|---:|---:|
| Luna | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |
| Terra | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) | 5.0 (n=2) |

## csv_import: pending reviews

Pending: packet mapping has not been created.

