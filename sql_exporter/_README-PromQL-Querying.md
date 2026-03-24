# PromQL Querying
- [PromQL Tutorial: A COMPLETE Guide to Prometheus Queries](https://www.youtube.com/watch?v=RC1ivt-ZN_U)
- [Query Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)

## Some functions
- `delta(v range-vector)` - Calculates the difference between the first and last value of each time series element in a range vector.
- `idelta(v range-vector)` - Calculates the difference between the last two samples in a range vector.
- `deriv(v range-vector)` - Calculates the per-second derivative of the time series in a range vector.
- `rate(v range-vector)` - Calculates the per-second average rate of increase of the time series in a range vector.
- `irate(v range-vector)` - Calculates the per-second instant rate of increase of the time series in a range vector.
- `increase(v range-vector)` - Calculates the increase in the time series in a range vector.
- `increase_by_time(v range-vector, t delta_time)` - Calculates the increase in the time series in a range vector over a specified time interval.

## Examples

### Subquery
```
# Returns the rate of increase of http_requests_total over the last 5 minutes for the last 30 minutes with a 1 minute resolution.
rate(http_requests_total[5m])[30m:1m]

```

### [Using functions, operators, etc](https://prometheus.io/docs/prometheus/latest/querying/examples/#using-functions-operators-etc)
```
sum by (job) (
  rate(http_requests_total[5m])
)
```

## exporter_instance variable
```
Name -> exporter_instance
Query
  Query type -> Label Values
  Label* -> instance
  Metric -> mssql_up
```

## PromQL Metric Value Extraction
```
Name -> sql_instance
Query
  Query type -> Query result
  Query -> mssql_local_time_seconds{instance="$exporter_instance"}
  Regex -> /.* ([0-9]+(\.[0-9]+)?).*/


# In grafana row
Collected @ ${local_time_seconds:date:YYYY-MM-DD HH:mm:ss}

# In Stats Panel
$local_time_seconds

Standard Options
  Unit -> dateTimeAsIso
```



