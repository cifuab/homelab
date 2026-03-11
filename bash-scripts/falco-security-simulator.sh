#!/bin/bash

ts="$(date +%s)000000000"

curl -s -H "Content-Type: application/json" -XPOST \
  "http://127.0.0.1:33100/loki/api/v1/push" \
  --data-raw "{
    \"streams\": [
      {
        \"stream\": {
          \"source\":\"syscall\",
          \"priority\":\"Critical\",
          \"rule\":\"Drop and execute new binary in container\",
          \"hostname\":\"talos-w1\"
        },
        \"values\": [[\"$ts\", \"SIMULATED Falco: Critical exec anomaly (cilium-cni)\" ]]
      },
      {
        \"stream\": {
          \"source\":\"syscall\",
          \"priority\":\"Critical\",
          \"rule\":\"Terminal shell in container\",
          \"hostname\":\"talos-w2\"
        },
        \"values\": [[\"$ts\", \"SIMULATED Falco: Terminal shell spawned in app pod\" ]]
      },
      {
        \"stream\": {
          \"source\":\"syscall\",
          \"priority\":\"Warning\",
          \"rule\":\"Write below /etc\",
          \"hostname\":\"talos-w2\"
        },
        \"values\": [[\"$ts\", \"SIMULATED Falco: Write below /etc detected\" ]]
      }
    ]
  }" >/dev/null && echo "Injected simulated Falco events into Loki"

