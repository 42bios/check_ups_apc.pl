# check_ups_apc.pl

Nagios/Icinga plugin to monitor APC UPS systems via SNMP.

## Features

- APC Smart-UPS status checks via SNMP v1/v2c/v3
- Battery capacity, load, temperature, remaining runtime
- Optional runtime and replacement metadata in output
- Performance data output for graphing

## Requirements

- Perl 5.10+
- `Net::SNMP`
- `Getopt::Long`
- `Time::Piece`

## Usage

```bash
./check_ups_apc.pl -H <host> -C <community>
```

SNMPv3 example:

```bash
./check_ups_apc.pl -H <host> -v 3 -U <username> -A <authpass> -a sha -X <privpass> -x aes
```

## Common Options

- `-H`: Hostname or IP
- `-v`: SNMP version
- `-C`: Community (v1/v2c)
- `-U`: Username (v3)
- `-A`: Auth password (v3)
- `-X`: Privacy password (v3)
- `-w`: Warning battery temperature
- `-c`: Critical battery temperature

## Output

Returns standard Nagios exit codes:

- `0` OK
- `1` WARNING
- `2` CRITICAL
- `3` UNKNOWN

## License

GNU General Public License v2.0 (see repository license selection).