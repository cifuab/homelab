7) Build the “Cilium Datapath Health” row

In Grafana dashboard:

Add → Row

Name it: Cilium Datapath Health

Add the panels below inside this row.

Panel 1 — Cilium components UP (Stat)

Purpose: Single “green/red” signal: are Cilium core components being scraped?

Visualization: Stat

Query (Instant):

min(up{job=~"cilium-agent|cilium-operator"})


Suggested title:

Cilium components UP

Suggested thresholds:

Base (red)

1 (green)

Panel 2 — Cilium Agent UP % (Gauge)

Visualization: Gauge

Query (Instant):

100 * sum(up{job="cilium-agent"} == 1) / count(up{job="cilium-agent"})


Field options:

Unit: Percent (0-100)

Min: 0

Max: 100

Thresholds (enterprise-simple):

Base = Red

90 = Yellow

99 = Green

Title:

Cilium Agent UP %

Panel 3 — Cilium Operator UP % (Gauge)

Visualization: Gauge

Query (Instant):

100 * sum(up{job="cilium-operator"} == 1) / count(up{job="cilium-operator"})


Same unit/min/max/thresholds as above.

Title:

Cilium Operator UP %

Panel 4 — Hubble Metrics UP % (Gauge)

Visualization: Gauge

Query (Instant):

100 * sum(up{job="hubble-metrics"} == 1) / count(up{job="hubble-metrics"})


Same unit/min/max/thresholds as above.

Title:

Hubble Metrics UP %

Panel 5 — Top drop reasons (Table)

Purpose: Why drops are happening.

Visualization: Table

Query (Instant or Range; Instant is fine for “current top reasons”):

topk(10, sum by (reason) (rate(cilium_drop_count_total[5m])))


Recommended:

Rename Value column to: drops/sec

Optional: hide Time column (table Transformations → Organize fields)

Title:

Top drop reasons

Panel 6 — Cilium drops/sec by node (Time series)

Purpose: Where drops happen (which node).

Visualization: Time series

Query (Range):

sum by (node) (rate(cilium_drop_count_total[5m]))


Title:

Cilium drops/sec by node

Panel 7 — Cilium drops/sec (cluster) (Time series)

Purpose: Cluster-wide drop rate trend.

Visualization: Time series

Query (Range):

sum(rate(cilium_drop_count_total[5m]))


Title:

Cilium drops/sec (cluster)