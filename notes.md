Start Grafana and InfluxDB
```
docker-compose up -d
```

Login to [local Grafana](http://localhost:3000) as admin/admin

Sample telegraf import config
```
[[outputs.influxdb]]
  urls = ["http://localhost:8086"]
  database = "telegraf"
  username = "telegraf"
  password = ""

[[inputs.tail]]
  # modify for your input file
  files = ["../input.influxline"]
  from_beginning = true
  data_format = "influx"
```

Import data
```
telegraf --debug --config ./config/telegraf-import.conf
```

Show InfluxDBs
```
curl -X POST http://localhost:8086/query --data-urlencode "q=SHOW DATABASES"
```

Drop data
```
curl -X POST http://localhost:8086/query --data-urlencode "q=DROP DATABASE telegraf"
```
