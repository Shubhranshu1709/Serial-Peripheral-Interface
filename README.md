# Serial-Peripheral-Interface
SPI (Serial Peripheral Interface) is a high-speed, full-duplex, synchronous serial communication protocol commonly used for short-distance communication between microcontrollers, sensors, memory devices, and other peripherals.

Key Features of SPI:
-Full-duplex communication (data transfer in both directions simultaneously).
-Master-Slave architecture (one master, multiple slaves).
-Clock-driven synchronization (controlled by the master).
-High-speed data transfer rates compared to I²C.
-Simple hardware implementation with minimal overhead.


SPI uses four main signals:
-MOSI (Master Out Slave In): Data sent from the master to the slave.
-MISO (Master In Slave Out): Data sent from the slave to the master.
-SCLK (Serial Clock): Clock signal generated by the master.
-CS (Chip Select) / SS (Slave Select): Active-low signal to select a specific slave.
