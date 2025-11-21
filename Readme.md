# Battleship in Shell-Script CLI Game for 2 players over internet

![CI – Lint & Tests](https://github.com/DocDBrown/BattleshipShellCLIGame/actions/workflows/ci.yml/badge.svg?branch=main&event=push)

<img src="battleship1.webp" alt="May God forgive you, but I wont" style="width: 90%;"/>

## Building in progress....

When Automated Application Generation and Validation is Complete Run the game with 

```json
bash battleship.sh
```

This implements the game Battleship in shell script as a CLI game:
- A two-player Battleship game that runs entirely as a POSIX shell CLI. Each player runs a script on their own machine. The script draws two 10×10 grids, accepts ship placement, and exchanges turn messages over the network. The game enforces Hasbro-style rules: one fleet per side, ships occupy consecutive horizontal or vertical cells, no overlap, players announce hit/miss, and ships sink when all their cells are hit. Fleet sizes follow common Hasbro sets such as Carrier(5), Battleship(4), Destroyer/Cruiser(3), Submarine(3), Patrol Boat(2). 
- Networking is peer-to-peer with known IP addresses and fixed ports. The script opens a TCP socket to the opponent or listens for one, then sends compact text messages such as “F5”, “HIT”, “SUNK:SUB”. Implementation uses tools available on most Unix systems: Bash’s /dev/tcp/$host/$port pseudo-device for a simple TCP client/server. These mechanisms create unencrypted byte streams suitable for turn exchange. Players can also send chat messages during games
- Game flow: both players start in “setup” to place ships locally without revealing coordinates. One player hosts; the other connects. On each turn the active player transmits a coordinate. The receiver validates against their secret board, replies “HIT” or “MISS”, and declares “SUNK:<ship>” when a vessel is finished. Each script maintains two boards: own ships and a targeting grid for shot history. The session ends when one side reports all ships sunk. This mirrors the standard Battleship turn structure while adapting the peg-and-grid model to text I/O. 
- Operational constraints: both players must know each other’s IP and open firewall/NAT for the chosen TCP port, or run from routable hosts. Latency is irrelevant because turns are sequential. Security is minimal by design; traffic is plaintext, so it is intended for trusted networks or throwaway ports. The script avoids a central server and requires only a Bourne-compatible shell plus bash. 
