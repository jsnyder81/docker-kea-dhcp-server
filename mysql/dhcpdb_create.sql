# Copyright (C) 2012-2020 Internet Systems Consortium, Inc. ("ISC")
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# This is the Kea schema specification for MySQL.
#
# The schema is reasonably portable (with the exception of the engine
# specification, which is MySQL-specific).  Minor changes might be needed for
# other databases.

# To create the schema, either type the command:
#
# mysql -u <user> -p <password> <database> < dhcpdb_create.mysql
#
# ... at the command prompt, or log in to the MySQL database and at the 'mysql>'
# prompt, issue the command:
#
# source dhcpdb_create.mysql
#
# This script is also called from kea-admin, see kea-admin db-init mysql
#
# Over time, Kea database schema will evolve. Each version is marked with
# major.minor version. This file is organized sequentially, i.e. database
# is initialized to 1.0, then upgraded to 2.0 etc. This may be somewhat
# sub-optimal, but it ensues consistency with upgrade scripts. (It is much
# easier to maintain init and upgrade scripts if they look the same).
# Since initialization is done only once, it's performance is not an issue.

# This line starts database initialization to 1.0.

# Holds the IPv4 leases.
CREATE TABLE lease4 (
    address INT UNSIGNED PRIMARY KEY NOT NULL,  # IPv4 address
    hwaddr VARBINARY(20),                       # Hardware address
    client_id VARBINARY(128),                   # Client ID
    valid_lifetime INT UNSIGNED,                # Length of the lease (seconds)
    expire TIMESTAMP,                           # Expiration time of the lease
    subnet_id INT UNSIGNED,                     # Subnet identification
    fqdn_fwd BOOL,                              # Has forward DNS update been performed by a server
    fqdn_rev BOOL,                              # Has reverse DNS update been performed by a server
    hostname VARCHAR(255)                       # The FQDN of the client
    ) ENGINE = INNODB;


# Create search indexes for lease4 table
# index by hwaddr and subnet_id
CREATE INDEX lease4_by_hwaddr_subnet_id ON lease4 (hwaddr, subnet_id);

# index by client_id and subnet_id
CREATE INDEX lease4_by_client_id_subnet_id ON lease4 (client_id, subnet_id);

# Holds the IPv6 leases.
# N.B. The use of a VARCHAR for the address is temporary for development:
# it will eventually be replaced by BINARY(16).
CREATE TABLE lease6 (
    address VARCHAR(39) PRIMARY KEY NOT NULL,   # IPv6 address
    duid VARBINARY(128),                        # DUID
    valid_lifetime INT UNSIGNED,                # Length of the lease (seconds)
    expire TIMESTAMP,                           # Expiration time of the lease
    subnet_id INT UNSIGNED,                     # Subnet identification
    pref_lifetime INT UNSIGNED,                 # Preferred lifetime
    lease_type TINYINT,                         # Lease type (see lease6_types
                                                #    table for possible values)
    iaid INT UNSIGNED,                          # See Section 12 of RFC 8415
    prefix_len TINYINT UNSIGNED,                # For IA_PD only
    fqdn_fwd BOOL,                              # Has forward DNS update been performed by a server
    fqdn_rev BOOL,                              # Has reverse DNS update been performed by a server
    hostname VARCHAR(255)                       # The FQDN of the client

    ) ENGINE = INNODB;

# Create search indexes for lease4 table
# index by iaid, subnet_id, and duid
CREATE INDEX lease6_by_iaid_subnet_id_duid ON lease6 (iaid, subnet_id, duid);

# ... and a definition of lease6 types.  This table is a convenience for
# users of the database - if they want to view the lease table and use the
# type names, they can join this table with the lease6 table.
# Make sure those values match Lease6::LeaseType enum (see src/bin/dhcpsrv/
# lease_mgr.h)
CREATE TABLE lease6_types (
    lease_type TINYINT PRIMARY KEY NOT NULL,    # Lease type code.
    name VARCHAR(5)                             # Name of the lease type
    ) ENGINE = INNODB;

START TRANSACTION;
INSERT INTO lease6_types VALUES (0, 'IA_NA');   # Non-temporary v6 addresses
INSERT INTO lease6_types VALUES (1, 'IA_TA');   # Temporary v6 addresses
INSERT INTO lease6_types VALUES (2, 'IA_PD');   # Prefix delegations
COMMIT;

# Finally, the version of the schema.  We start at 1.0 during development.
# This table is only modified during schema upgrades.  For historical reasons
# (related to the names of the columns in the BIND 10 DNS database file), the
# first column is called 'version' and not 'major'.
CREATE TABLE schema_version (
    version INT PRIMARY KEY NOT NULL,       # Major version number
    minor INT                               # Minor version number
    ) ENGINE = INNODB;
START TRANSACTION;
INSERT INTO schema_version VALUES (1, 0);
COMMIT;

# This line concludes database initialization to version 1.0.

# This line starts database upgrade to version 2.0.
ALTER TABLE lease6
    ADD COLUMN hwaddr varbinary(20), # Hardware/MAC address, typically only 6
                                     # bytes is used, but some hardware (e.g.
                                     # Infiniband) use up to 20.
    ADD COLUMN hwtype smallint unsigned, # hardware type (16 bits)
    ADD COLUMN hwaddr_source int unsigned; # Hardware source. See description
                                     # of lease_hwaddr_source below.

# Kea keeps track of the hardware/MAC address source, i.e. how the address
# was obtained. Depending on the technique and your network topology, it may
# be more or less trustworthy. This table is a convenience for
# users of the database - if they want to view the lease table and use the
# type names, they can join this table with the lease6 table. For details,
# see constants defined in src/lib/dhcp/dhcp/pkt.h for detailed explanation.
CREATE TABLE lease_hwaddr_source (
    hwaddr_source INT PRIMARY KEY NOT NULL,
    name VARCHAR(40)
) ENGINE = INNODB;

# Hardware address obtained from raw sockets
INSERT INTO lease_hwaddr_source VALUES (1, 'HWADDR_SOURCE_RAW');

# Hardware address converted from IPv6 link-local address with EUI-64
INSERT INTO lease_hwaddr_source VALUES (2, 'HWADDR_SOURCE_IPV6_LINK_LOCAL');

# Hardware address extracted from client-id (duid)
INSERT INTO lease_hwaddr_source VALUES (4, 'HWADDR_SOURCE_DUID');

# Hardware address extracted from client address relay option (RFC6939)
INSERT INTO lease_hwaddr_source VALUES (8, 'HWADDR_SOURCE_CLIENT_ADDR_RELAY_OPTION');

# Hardware address extracted from remote-id option (RFC4649)
INSERT INTO lease_hwaddr_source VALUES (16, 'HWADDR_SOURCE_REMOTE_ID');

# Hardware address extracted from subscriber-id option (RFC4580)
INSERT INTO lease_hwaddr_source VALUES (32, 'HWADDR_SOURCE_SUBSCRIBER_ID');

# Hardware address extracted from docsis options
INSERT INTO lease_hwaddr_source VALUES (64, 'HWADDR_SOURCE_DOCSIS');

UPDATE schema_version SET version='2', minor='0';

# This line concludes database upgrade to version 2.0.

# This line starts database upgrade to version 3.0.
# Upgrade extending MySQL schema with the ability to store hosts.

CREATE TABLE IF NOT EXISTS hosts (
    host_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    dhcp_identifier VARBINARY(128) NOT NULL,
    dhcp_identifier_type TINYINT NOT NULL,
    dhcp4_subnet_id INT UNSIGNED NULL,
    dhcp6_subnet_id INT UNSIGNED NULL,
    ipv4_address INT UNSIGNED NULL,
    hostname VARCHAR(255) NULL,
    dhcp4_client_classes VARCHAR(255) NULL,
    dhcp6_client_classes VARCHAR(255) NULL,
    PRIMARY KEY (host_id),
    INDEX key_dhcp4_identifier_subnet_id (dhcp_identifier ASC , dhcp_identifier_type ASC),
    INDEX key_dhcp6_identifier_subnet_id (dhcp_identifier ASC , dhcp_identifier_type ASC , dhcp6_subnet_id ASC)
)  ENGINE=INNODB;
-- -----------------------------------------------------
-- Table `ipv6_reservations`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS ipv6_reservations (
    reservation_id INT NOT NULL AUTO_INCREMENT,
    address VARCHAR(39) NOT NULL,
    prefix_len TINYINT(3) UNSIGNED NOT NULL DEFAULT 128,
    type TINYINT(4) UNSIGNED NOT NULL DEFAULT 0,
    dhcp6_iaid INT UNSIGNED NULL,
    host_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (reservation_id),
    INDEX fk_ipv6_reservations_host_idx (host_id ASC),
    CONSTRAINT fk_ipv6_reservations_Host FOREIGN KEY (host_id)
        REFERENCES hosts (host_id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
)  ENGINE=INNODB;
-- -----------------------------------------------------
-- Table `dhcp4_options`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_options (
    option_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    code TINYINT UNSIGNED NOT NULL,
    value BLOB NULL,
    formatted_value TEXT NULL,
    space VARCHAR(128) NULL,
    persistent TINYINT(1) NOT NULL DEFAULT 0,
    dhcp_client_class VARCHAR(128) NULL,
    dhcp4_subnet_id INT NULL,
    host_id INT UNSIGNED NULL,
    PRIMARY KEY (option_id),
    UNIQUE INDEX option_id_UNIQUE (option_id ASC),
    INDEX fk_options_host1_idx (host_id ASC),
    CONSTRAINT fk_options_host1 FOREIGN KEY (host_id)
        REFERENCES hosts (host_id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
)  ENGINE=INNODB;
-- -----------------------------------------------------
-- Table `dhcp6_options`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_options (
    option_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    code INT UNSIGNED NOT NULL,
    value BLOB NULL,
    formatted_value TEXT NULL,
    space VARCHAR(128) NULL,
    persistent TINYINT(1) NOT NULL DEFAULT 0,
    dhcp_client_class VARCHAR(128) NULL,
    dhcp6_subnet_id INT NULL,
    host_id INT UNSIGNED NULL,
    PRIMARY KEY (option_id),
    UNIQUE INDEX option_id_UNIQUE (option_id ASC),
    INDEX fk_options_host1_idx (host_id ASC),
    CONSTRAINT fk_options_host10 FOREIGN KEY (host_id)
        REFERENCES hosts (host_id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
)  ENGINE=INNODB;

DELIMITER $$
CREATE TRIGGER host_BDEL BEFORE DELETE ON hosts FOR EACH ROW
-- Edit trigger body code below this line. Do not edit lines above this one
BEGIN
DELETE FROM ipv6_reservations WHERE ipv6_reservations.host_id = OLD.host_id;
END
$$
DELIMITER ;

UPDATE schema_version
SET version = '3', minor = '0';
# This line concludes database upgrade to version 3.0.

# This line starts database upgrade to version 4.0.
# Upgrade extending MySQL schema with the state columns for lease tables.

# Add state column to the lease4 table.
ALTER TABLE lease4
    ADD COLUMN state INT UNSIGNED DEFAULT 0;

# Add state column to the lease6 table.
ALTER TABLE lease6
    ADD COLUMN state INT UNSIGNED DEFAULT 0;

# Create indexes for querying leases in a given state and segregated
# by the expiration time. One of the applications is to retrieve all
# expired leases. However, these indexes can be also used to retrieve
# leases in a given state regardless of the expiration time.
CREATE INDEX lease4_by_state_expire ON lease4 (state ASC, expire ASC);
CREATE INDEX lease6_by_state_expire ON lease6 (state ASC, expire ASC);

# Create table holding mapping of the lease states to their names.
# This is not used in queries from the DHCP server but rather in
# direct queries from the lease database management tools.
CREATE TABLE IF NOT EXISTS lease_state (
  state INT UNSIGNED PRIMARY KEY NOT NULL,
  name VARCHAR(64) NOT NULL
) ENGINE=INNODB;

# Insert currently defined state names.
INSERT INTO lease_state VALUES (0, 'default');
INSERT INTO lease_state VALUES (1, 'declined');
INSERT INTO lease_state VALUES (2, 'expired-reclaimed');

# Add a constraint that any state value added to the lease4 must
# map to a value in the lease_state table.
ALTER TABLE lease4
    ADD CONSTRAINT fk_lease4_state FOREIGN KEY (state)
    REFERENCES lease_state (state);

# Add a constraint that any state value added to the lease6 must
# map to a value in the lease_state table.
ALTER TABLE lease6
    ADD CONSTRAINT fk_lease6_state FOREIGN KEY (state)
    REFERENCES lease_state (state);

# Add a constraint that lease type in the lease6 table must map
# to a lease type defined in the lease6_types table.
ALTER TABLE lease6
    ADD CONSTRAINT fk_lease6_type FOREIGN KEY (lease_type)
    REFERENCES lease6_types (lease_type);

# Modify the name of one of the HW address sources, and add a new one.
UPDATE lease_hwaddr_source
    SET name = 'HWADDR_SOURCE_DOCSIS_CMTS'
    WHERE hwaddr_source = 64;

INSERT INTO lease_hwaddr_source VALUES (128, 'HWADDR_SOURCE_DOCSIS_MODEM');

# Add UNSIGNED to match with the lease6.
ALTER TABLE lease_hwaddr_source
    MODIFY COLUMN hwaddr_source INT UNSIGNED NOT NULL;

# Add a constraint that non-null hwaddr_source in the lease6 table
# must map to an entry in the lease_hwaddr_source.
ALTER TABLE lease6
    ADD CONSTRAINT fk_lease6_hwaddr_source FOREIGN KEY (hwaddr_source)
    REFERENCES lease_hwaddr_source (hwaddr_source);

# FUNCTION that returns a result set containing the column names for lease4 dumps
DROP PROCEDURE IF EXISTS lease4DumpHeader;
DELIMITER $$
CREATE PROCEDURE lease4DumpHeader()
BEGIN
SELECT 'address,hwaddr,client_id,valid_lifetime,expire,subnet_id,fqdn_fwd,fqdn_rev,hostname,state';
END  $$
DELIMITER ;

# FUNCTION that returns a result set containing the data for lease4 dumps
DROP PROCEDURE IF EXISTS lease4DumpData;
DELIMITER $$
CREATE PROCEDURE lease4DumpData()
BEGIN
SELECT
    INET_NTOA(l.address),
    IFNULL(HEX(l.hwaddr), ''),
    IFNULL(HEX(l.client_id), ''),
    l.valid_lifetime,
    l.expire,
    l.subnet_id,
    l.fqdn_fwd,
    l.fqdn_rev,
    l.hostname,
    s.name
FROM
    lease4 l
    LEFT OUTER JOIN lease_state s on (l.state = s.state)
ORDER BY l.address;
END $$
DELIMITER ;

# FUNCTION that returns a result set containing the column names for lease6 dumps
DROP PROCEDURE IF EXISTS lease6DumpHeader;
DELIMITER $$
CREATE PROCEDURE lease6DumpHeader()
BEGIN
SELECT 'address,duid,valid_lifetime,expire,subnet_id,pref_lifetime,lease_type,iaid,prefix_len,fqdn_fwd,fqdn_rev,hostname,hwaddr,hwtype,hwaddr_source,state';
END  $$
DELIMITER ;

# FUNCTION that returns a result set containing the data for lease6 dumps
DROP PROCEDURE IF EXISTS lease6DumpData;
DELIMITER $$
CREATE PROCEDURE lease6DumpData()
BEGIN
SELECT
    l.address,
    IFNULL(HEX(l.duid), ''),
    l.valid_lifetime,
    l.expire,
    l.subnet_id,
    l.pref_lifetime,
    IFNULL(t.name, ''),
    l.iaid,
    l.prefix_len,
    l.fqdn_fwd,
    l.fqdn_rev,
    l.hostname,
    IFNULL(HEX(l.hwaddr), ''),
    IFNULL(l.hwtype, ''),
    IFNULL(h.name, ''),
    IFNULL(s.name, '')
FROM lease6 l
    left outer join lease6_types t on (l.lease_type = t.lease_type)
    left outer join lease_state s on (l.state = s.state)
    left outer join lease_hwaddr_source h on (l.hwaddr_source = h.hwaddr_source)
ORDER BY l.address;
END $$
DELIMITER ;

# Update the schema version number
UPDATE schema_version
SET version = '4', minor = '0';

# This line concludes database upgrade to version 4.0.

# In the event hardware address cannot be determined, we need to satisfy
# foreign key constraint between lease6 and lease_hardware_source
INSERT INTO lease_hwaddr_source VALUES (0, 'HWADDR_SOURCE_UNKNOWN');

# Update the schema version number
UPDATE schema_version
SET version = '4', minor = '1';

# This line concludes database upgrade to version 4.1.

# Update index used for searching DHCPv4 reservations by identifier and subnet id.
# This index is now unique (to prevent duplicates) and includes DHCPv4 subnet
# identifier.
DROP INDEX key_dhcp4_identifier_subnet_id ON hosts;
CREATE UNIQUE INDEX key_dhcp4_identifier_subnet_id ON hosts (dhcp_identifier ASC , dhcp_identifier_type ASC , dhcp4_subnet_id ASC);

# Update index used for searching DHCPv6 reservations by identifier and subnet id.
# This index is now unique to prevent duplicates.
DROP INDEX key_dhcp6_identifier_subnet_id ON hosts;
CREATE UNIQUE INDEX key_dhcp6_identifier_subnet_id ON hosts (dhcp_identifier ASC , dhcp_identifier_type ASC , dhcp6_subnet_id ASC);

# Create index to search for reservations using IP address and subnet id.
# This unique index guarantees that there is only one occurrence of the
# particular IPv4 address for a given subnet.
CREATE UNIQUE INDEX key_dhcp4_ipv4_address_subnet_id ON hosts (ipv4_address ASC , dhcp4_subnet_id ASC);

# Create index to search for reservations using address/prefix and prefix
# length.
CREATE UNIQUE INDEX key_dhcp6_address_prefix_len ON ipv6_reservations (address ASC , prefix_len ASC);

# Create a table mapping host identifiers to their names. Values in this
# table are used as a foreign key in hosts table to guarantee that only
# identifiers present in host_identifier_type table are used in hosts
# table.
CREATE TABLE IF NOT EXISTS host_identifier_type (
    type TINYINT PRIMARY KEY NOT NULL,   # Lease type code.
    name VARCHAR(32)                     # Name of the lease type
) ENGINE = INNODB;

START TRANSACTION;
INSERT INTO host_identifier_type VALUES (0, 'hw-address');
INSERT INTO host_identifier_type VALUES (1, 'duid');
INSERT INTO host_identifier_type VALUES (2, 'circuit-id');
COMMIT;

# Add a constraint that any identifier type value added to the hosts
# must map to a value in the host_identifier_type table.
ALTER TABLE hosts
    ADD CONSTRAINT fk_host_identifier_type FOREIGN KEY (dhcp_identifier_type)
    REFERENCES host_identifier_type (type);

# Store DHCPv6 option code as 16-bit unsigned integer.
ALTER TABLE dhcp6_options MODIFY code SMALLINT UNSIGNED NOT NULL;

# Subnet identifier is unsigned.
ALTER TABLE dhcp4_options MODIFY dhcp4_subnet_id INT UNSIGNED NULL;
ALTER TABLE dhcp6_options MODIFY dhcp6_subnet_id INT UNSIGNED NULL;

# Scopes associate DHCP options stored in dhcp4_options and
# dhcp6_options tables with hosts, subnets, classes or indicate
# that they are global options.
CREATE TABLE IF NOT EXISTS dhcp_option_scope (
    scope_id TINYINT UNSIGNED PRIMARY KEY NOT NULL,
    scope_name VARCHAR(32)
) ENGINE = INNODB;

START TRANSACTION;
INSERT INTO dhcp_option_scope VALUES (0, 'global');
INSERT INTO dhcp_option_scope VALUES (1, 'subnet');
INSERT INTO dhcp_option_scope VALUES (2, 'client-class');
INSERT INTO dhcp_option_scope VALUES (3, 'host');
COMMIT;

# Add scopes into table holding DHCPv4 options
ALTER TABLE dhcp4_options ADD COLUMN scope_id TINYINT UNSIGNED NOT NULL;
ALTER TABLE dhcp4_options
    ADD CONSTRAINT fk_dhcp4_option_scope FOREIGN KEY (scope_id)
    REFERENCES dhcp_option_scope (scope_id);

# Add scopes into table holding DHCPv6 options
ALTER TABLE dhcp6_options ADD COLUMN scope_id TINYINT UNSIGNED NOT NULL;
ALTER TABLE dhcp6_options
    ADD CONSTRAINT fk_dhcp6_option_scope FOREIGN KEY (scope_id)
    REFERENCES dhcp_option_scope (scope_id);

# Add UNSIGNED to reservation_id
ALTER TABLE ipv6_reservations
    MODIFY reservation_id INT UNSIGNED NOT NULL AUTO_INCREMENT;

# This line concludes database upgrade to version 7.0.

# Add columns holding reservations for siaddr, sname and file fields
# carried within DHCPv4 message.
ALTER TABLE hosts ADD COLUMN dhcp4_next_server INT UNSIGNED NULL;
ALTER TABLE hosts ADD COLUMN dhcp4_server_hostname VARCHAR(64) NULL;
ALTER TABLE hosts ADD COLUMN dhcp4_boot_file_name VARCHAR(128) NULL;

# Update the schema version number
UPDATE schema_version
SET version = '5', minor = '0';
# This line concludes database upgrade to version 5.0.

# Add missing 'client-id' and new 'flex-id' host identifier types.
INSERT INTO host_identifier_type VALUES (3, 'client-id');
INSERT INTO host_identifier_type VALUES (4, 'flex-id');

# Recreate the trigger removing dependent host entries.
DROP TRIGGER host_BDEL;

DELIMITER $$
CREATE TRIGGER host_BDEL BEFORE DELETE ON hosts FOR EACH ROW
-- Edit trigger body code below this line. Do not edit lines above this one
BEGIN
DELETE FROM ipv6_reservations WHERE ipv6_reservations.host_id = OLD.host_id;
DELETE FROM dhcp4_options WHERE dhcp4_options.host_id = OLD.host_id;
DELETE FROM dhcp6_options WHERE dhcp6_options.host_id = OLD.host_id;
END
$$
DELIMITER ;

# Update the schema version number
UPDATE schema_version
SET version = '5', minor = '1';
# This line concludes database upgrade to version 5.1.

# Make subnet_id column types consistent with lease table columns
ALTER TABLE dhcp4_options MODIFY dhcp4_subnet_id INT UNSIGNED;
ALTER TABLE dhcp6_options MODIFY dhcp6_subnet_id INT UNSIGNED;

# Update the schema version number
UPDATE schema_version
SET version = '5', minor = '2';

# This line concludes database upgrade to version 5.2.

# Add user context into table holding hosts
ALTER TABLE hosts ADD COLUMN user_context TEXT NULL;

# Add user contexts into tables holding DHCP options
ALTER TABLE dhcp4_options ADD COLUMN user_context TEXT NULL;
ALTER TABLE dhcp6_options ADD COLUMN user_context TEXT NULL;

# Create index for searching leases by subnet identifier.
CREATE INDEX lease4_by_subnet_id ON lease4 (subnet_id);

# Create for searching leases by subnet identifier and lease type.
CREATE INDEX lease6_by_subnet_id_lease_type ON lease6 (subnet_id, lease_type);

# The index by iaid_subnet_id_duid is not the best choice because there are
# cases when we don't specify subnet identifier while searching leases. The
# index will be universal if the subnet_id is the right most column in the
# index.
DROP INDEX lease6_by_iaid_subnet_id_duid on lease6;
CREATE INDEX lease6_by_duid_iaid_subnet_id ON lease6 (duid, iaid, subnet_id);

# Create lease4_stat table
CREATE TABLE lease4_stat (
    subnet_id INT UNSIGNED NOT NULL,
    state INT UNSIGNED NOT NULL,
    leases BIGINT,
    PRIMARY KEY (subnet_id, state)
) ENGINE = INNODB;

# Create stat_lease4_insert trigger
DELIMITER $$
CREATE TRIGGER stat_lease4_insert AFTER INSERT ON lease4
    FOR EACH ROW
    BEGIN
        IF NEW.state = 0 OR NEW.state = 1 THEN
            # Update the state count if it exists
            UPDATE lease4_stat SET leases = leases + 1
            WHERE subnet_id = NEW.subnet_id AND state = NEW.state;

            # Insert the state count record if it does not exist
            IF ROW_COUNT() <= 0 THEN
                INSERT INTO lease4_stat VALUES (NEW.subnet_id, NEW.state, 1);
            END IF;
        END IF;
    END $$
DELIMITER ;

# Create stat_lease4_update trigger
DELIMITER $$
CREATE TRIGGER stat_lease4_update AFTER UPDATE ON lease4
    FOR EACH ROW
    BEGIN
        IF OLD.state != NEW.state THEN
            IF OLD.state = 0 OR OLD.state = 1 THEN
                # Decrement the old state count if record exists
                UPDATE lease4_stat SET leases = leases - 1
                WHERE subnet_id = OLD.subnet_id AND state = OLD.state;
            END IF;

            IF NEW.state = 0 OR NEW.state = 1 THEN
                # Increment the new state count if record exists
                UPDATE lease4_stat SET leases = leases + 1
                WHERE subnet_id = NEW.subnet_id AND state = NEW.state;

                # Insert new state record if it does not exist
                IF ROW_COUNT() <= 0 THEN
                    INSERT INTO lease4_stat VALUES (NEW.subnet_id, NEW.state, 1);
                END IF;
            END IF;
        END IF;
    END $$
DELIMITER ;

# Create stat_lease4_delete trigger
DELIMITER $$
CREATE TRIGGER stat_lease4_delete AFTER DELETE ON lease4
    FOR EACH ROW
    BEGIN
        IF OLD.state = 0 OR OLD.state = 1 THEN
            # Decrement the state count if record exists
            UPDATE lease4_stat SET leases = leases - 1
            WHERE subnet_id = OLD.subnet_id AND OLD.state = state;
        END IF;
    END $$
DELIMITER ;

# Create lease6_stat table
CREATE TABLE lease6_stat (
    subnet_id INT UNSIGNED NOT NULL,
    lease_type INT UNSIGNED NOT NULL,
    state INT UNSIGNED NOT NULL,
    leases BIGINT,
    PRIMARY KEY (subnet_id, lease_type, state)
) ENGINE = INNODB;

# Create stat_lease6_insert trigger
DELIMITER $$
CREATE TRIGGER stat_lease6_insert AFTER INSERT ON lease6
    FOR EACH ROW
    BEGIN
        IF NEW.state = 0 OR NEW.state = 1 THEN
            # Update the state count if it exists
            UPDATE lease6_stat SET leases = leases + 1
            WHERE
                subnet_id = NEW.subnet_id AND lease_type = NEW.lease_type
                AND state = NEW.state;

            # Insert the state count record if it does not exist
            IF ROW_COUNT() <= 0 THEN
                INSERT INTO lease6_stat
                VALUES (NEW.subnet_id, NEW.lease_type, NEW.state, 1);
            END IF;
        END IF;
    END $$
DELIMITER ;

# Create stat_lease6_update trigger
DELIMITER $$
CREATE TRIGGER stat_lease6_update AFTER UPDATE ON lease6
    FOR EACH ROW
    BEGIN
        IF OLD.state != NEW.state THEN
            IF OLD.state = 0 OR OLD.state = 1 THEN
                # Decrement the old state count if record exists
                UPDATE lease6_stat SET leases = leases - 1
                WHERE subnet_id = OLD.subnet_id AND lease_type = OLD.lease_type
                AND state = OLD.state;
            END IF;

            IF NEW.state = 0 OR NEW.state = 1 THEN
                # Increment the new state count if record exists
                UPDATE lease6_stat SET leases = leases + 1
                WHERE subnet_id = NEW.subnet_id AND lease_type = NEW.lease_type
                AND state = NEW.state;

                # Insert new state record if it does not exist
                IF ROW_COUNT() <= 0 THEN
                    INSERT INTO lease6_stat
                    VALUES (NEW.subnet_id, NEW.lease_type, NEW.state, 1);
                END IF;
            END IF;
        END IF;
    END $$
DELIMITER ;

# Create stat_lease6_delete trigger
DELIMITER $$
CREATE TRIGGER stat_lease6_delete AFTER DELETE ON lease6
    FOR EACH ROW
    BEGIN
        IF OLD.state = 0 OR OLD.state = 1 THEN
            # Decrement the state count if record exists
            UPDATE lease6_stat SET leases = leases - 1
            WHERE subnet_id = OLD.subnet_id AND lease_type = OLD.lease_type
            AND state = OLD.state;
        END IF;
    END $$
DELIMITER ;

# Update the schema version number
UPDATE schema_version
SET version = '6', minor = '0';

# This line concludes database upgrade to version 6.0.

# Add user context into tables holding leases
ALTER TABLE lease4 ADD COLUMN user_context TEXT NULL;
ALTER TABLE lease6 ADD COLUMN user_context TEXT NULL;

DROP PROCEDURE IF EXISTS lease4DumpHeader;
DELIMITER $$
CREATE PROCEDURE lease4DumpHeader()
BEGIN
SELECT 'address,hwaddr,client_id,valid_lifetime,expire,subnet_id,fqdn_fwd,fqdn_rev,hostname,state,user_context';
END  $$
DELIMITER ;

# FUNCTION that returns a result set containing the data for lease4 dumps
DROP PROCEDURE IF EXISTS lease4DumpData;
DELIMITER $$
CREATE PROCEDURE lease4DumpData()
BEGIN
SELECT
    INET_NTOA(l.address),
    IFNULL(HEX(l.hwaddr), ''),
    IFNULL(HEX(l.client_id), ''),
    l.valid_lifetime,
    l.expire,
    l.subnet_id,
    l.fqdn_fwd,
    l.fqdn_rev,
    l.hostname,
    s.name,
    IFNULL(l.user_context, '')
FROM
    lease4 l
    LEFT OUTER JOIN lease_state s on (l.state = s.state)
ORDER BY l.address;
END $$
DELIMITER ;

DROP PROCEDURE IF EXISTS lease6DumpHeader;
DELIMITER $$
CREATE PROCEDURE lease6DumpHeader()
BEGIN
SELECT 'address,duid,valid_lifetime,expire,subnet_id,pref_lifetime,lease_type,iaid,prefix_len,fqdn_fwd,fqdn_rev,hostname,hwaddr,hwtype,hwaddr_source,state,user_context';
END  $$
DELIMITER ;

# FUNCTION that returns a result set containing the data for lease6 dumps
DROP PROCEDURE IF EXISTS lease6DumpData;
DELIMITER $$
CREATE PROCEDURE lease6DumpData()
BEGIN
SELECT
    l.address,
    IFNULL(HEX(l.duid), ''),
    l.valid_lifetime,
    l.expire,
    l.subnet_id,
    l.pref_lifetime,
    IFNULL(t.name, ''),
    l.iaid,
    l.prefix_len,
    l.fqdn_fwd,
    l.fqdn_rev,
    l.hostname,
    IFNULL(HEX(l.hwaddr), ''),
    IFNULL(l.hwtype, ''),
    IFNULL(h.name, ''),
    IFNULL(s.name, ''),
    IFNULL(l.user_context, '')
FROM lease6 l
    left outer join lease6_types t on (l.lease_type = t.lease_type)
    left outer join lease_state s on (l.state = s.state)
    left outer join lease_hwaddr_source h on (l.hwaddr_source = h.hwaddr_source)
ORDER BY l.address;
END $$
DELIMITER ;

# Create logs table (logs table is used by forensic logging hook library)
CREATE TABLE logs (
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  # creation timestamp
    address VARCHAR(43) NULL,                       # address or prefix
    log TEXT NOT NULL                               # the log itself
    ) ENGINE = INNODB;

# Create search index
CREATE INDEX timestamp_index ON logs (timestamp);

#add auth key for reconfiguration
ALTER TABLE hosts
    ADD COLUMN auth_key VARCHAR(16) NULL;


# Add scope for shared network specific options.
INSERT INTO dhcp_option_scope (scope_id, scope_name)
    VALUES(4, "shared-network");

# Add scope for pool specific options.
INSERT INTO dhcp_option_scope (scope_id, scope_name)
    VALUES(5, "pool");

# Add scope for PD pool specific options.
INSERT INTO dhcp_option_scope (scope_id, scope_name)
    VALUES(6, "pd-pool");

-- -----------------------------------------------------
-- Table `modification`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS modification (
  id TINYINT(3) NOT NULL,
  modification_type VARCHAR(32) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

INSERT INTO modification(id, modification_type)
    VALUES(0, "create");

INSERT INTO modification(id, modification_type)
    VALUES(1, "update");

INSERT INTO modification(id, modification_type)
    VALUES(2, "delete");

-- -----------------------------------------------------
-- Table `dhcp4_server`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_server (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    tag VARCHAR(256) NOT NULL,
    description TEXT,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY dhcp4_server_tag_UNIQUE (tag),
    KEY key_dhcp4_server_modification_ts (modification_ts)
) ENGINE=InnoDB;

# Special server entry meaning "all servers". This refers to
# the configuration entries owned by all servers.
INSERT INTO dhcp4_server(id, tag, description, modification_ts)
    VALUES(1, "all", "special type: all servers", NOW());

-- -----------------------------------------------------
-- Table `dhcp4_audit`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_audit (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    object_type VARCHAR(256) NOT NULL,
    object_id BIGINT(20) UNSIGNED NOT NULL,
    modification_type TINYINT(1) NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    log_message TEXT,
    PRIMARY KEY (id),
    KEY key_dhcp4_audit_by_modification_ts (modification_ts),
    KEY fk_dhcp4_audit_modification_type (modification_type),
    CONSTRAINT fk_dhcp4_audit_modification_type FOREIGN KEY (modification_type)
        REFERENCES modification (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;


-- -----------------------------------------------------
-- Table `dhcp4_global_parameter`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_global_parameter (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(128) NOT NULL,
    value LONGTEXT NOT NULL,
    modification_ts timestamp NOT NULL,
    PRIMARY KEY (id),
    KEY key_dhcp4_global_parameter_modification_ts (modification_ts),
    KEY key_dhcp4_global_parameter_name (name)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_global_parameter_server`
-- M-to-M cross-reference between global parameters and
-- servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_global_parameter_server (
    parameter_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (parameter_id, server_id),
    KEY fk_dhcp4_global_parameter_server_server_id (server_id),
    KEY key_dhcp4_global_parameter_server (modification_ts),
    CONSTRAINT fk_dhcp4_global_parameter_server_parameter_id FOREIGN KEY (parameter_id)
        REFERENCES dhcp4_global_parameter (id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp4_global_parameter_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp4_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_option_def`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_option_def (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    code SMALLINT UNSIGNED NOT NULL,
    name VARCHAR(128) NOT NULL,
    space VARCHAR(128) NOT NULL,
    type TINYINT UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    is_array TINYINT(1) NOT NULL,
    encapsulate VARCHAR(128) NOT NULL,
    record_types VARCHAR(512) DEFAULT NULL,
    user_context LONGTEXT,
    PRIMARY KEY (id),
    KEY key_dhcp4_option_def_modification_ts (modification_ts),
    KEY key_dhcp4_option_def_code_space (code, space)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_option_def_server`
-- M-to-M cross-reference between option definitions and
-- servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_option_def_server (
    option_def_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (option_def_id, server_id),
    KEY fk_dhcp4_option_def_server_server_id_idx (server_id),
    KEY key_dhcp4_option_def_server_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp4_option_def_server_option_def_id FOREIGN KEY (option_def_id)
        REFERENCES dhcp4_option_def (id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp4_option_def_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp4_server (id) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_shared_network`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_shared_network (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(128) NOT NULL,
    client_class VARCHAR(128) DEFAULT NULL,
    interface VARCHAR(128) DEFAULT NULL,
    match_client_id TINYINT(1) NOT NULL DEFAULT '1',
    modification_ts TIMESTAMP NOT NULL,
    rebind_timer INT(10) DEFAULT NULL,
    relay LONGTEXT,
    renew_timer INT(10) DEFAULT NULL,
    require_client_classes LONGTEXT DEFAULT NULL,
    reservation_mode TINYINT(3) NOT NULL DEFAULT '3',
    user_context LONGTEXT,
    valid_lifetime INT(10) DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY name_UNIQUE (name),
    KEY key_dhcp4_shared_network_modification_ts (modification_ts)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_shared_network_server`
-- M-to-M cross-reference between shared networks and
-- servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_shared_network_server (
    shared_network_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (shared_network_id, server_id),
    KEY key_dhcp4_shared_network_server_modification_ts (modification_ts),
    KEY fk_dhcp4_shared_network_server_server_id (server_id),
    CONSTRAINT fk_dhcp4_shared_network_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp4_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp4_shared_network_server_shared_network_id FOREIGN KEY (shared_network_id)
        REFERENCES dhcp4_shared_network (id) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_subnet`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_subnet (
    subnet_id INT(10) UNSIGNED NOT NULL,
    subnet_prefix VARCHAR(32) NOT NULL,
    4o6_interface VARCHAR(128) DEFAULT NULL,
    4o6_interface_id VARCHAR(128) DEFAULT NULL,
    4o6_subnet VARCHAR(64) DEFAULT NULL,
    boot_file_name VARCHAR(512) DEFAULT NULL,
    client_class VARCHAR(128) DEFAULT NULL,
    interface VARCHAR(128) DEFAULT NULL,
    match_client_id TINYINT(1) NOT NULL DEFAULT '1',
    modification_ts TIMESTAMP NOT NULL,
    next_server INT(10) UNSIGNED DEFAULT NULL,
    rebind_timer INT(10) DEFAULT NULL,
    relay LONGTEXT,
    renew_timer INT(10) DEFAULT NULL,
    require_client_classes LONGTEXT DEFAULT NULL,
    reservation_mode TINYINT(3) NOT NULL DEFAULT '3',
    server_hostname VARCHAR(512) DEFAULT NULL,
    shared_network_name VARCHAR(128) DEFAULT NULL,
    user_context LONGTEXT,
    valid_lifetime INT(10) DEFAULT NULL,
    PRIMARY KEY (subnet_id),
    UNIQUE KEY subnet4_subnet_prefix (subnet_prefix),
    KEY fk_dhcp4_subnet_shared_network (shared_network_name),
    KEY key_dhcp4_subnet_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp4_subnet_shared_network FOREIGN KEY (shared_network_name)
        REFERENCES dhcp4_shared_network (name)
        ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_pool`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_pool (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    start_address INT(10) UNSIGNED NOT NULL,
    end_address INT(10) UNSIGNED NOT NULL,
    subnet_id INT(10) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (id),
    KEY key_dhcp4_pool_modification_ts (modification_ts),
    KEY fk_dhcp4_pool_subnet_id (subnet_id),
    CONSTRAINT fk_dhcp4_pool_subnet_id FOREIGN KEY (subnet_id)
        REFERENCES dhcp4_subnet (subnet_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp4_subnet_server`
-- M-to-M cross-reference between subnets and servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_subnet_server (
    subnet_id INT(10) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (subnet_id,server_id),
    KEY fk_dhcp4_subnet_server_server_id_idx (server_id),
    KEY key_dhcp4_subnet_server_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp4_subnet_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp4_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp4_subnet_server_subnet_id FOREIGN KEY (subnet_id)
        REFERENCES dhcp4_subnet (subnet_id)
        ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;


# Modify the primary key to BINGINT as other tables have.
ALTER TABLE dhcp4_options MODIFY option_id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT;

# Add conifguration backend specific columns.
ALTER TABLE dhcp4_options
    ADD COLUMN shared_network_name VARCHAR(128) DEFAULT NULL,
    ADD COLUMN pool_id BIGINT(20) UNSIGNED DEFAULT NULL,
    ADD COLUMN modification_ts TIMESTAMP NOT NULL;

-- -----------------------------------------------------
-- Table `dhcp4_options_server`
-- M-to-M cross-reference between options and servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_options_server (
    option_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (option_id, server_id),
    KEY fk_dhcp4_options_server_server_id (server_id),
    KEY key_dhcp4_options_server_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp4_options_server_option_id FOREIGN KEY (option_id)
        REFERENCES dhcp4_options (option_id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp4_options_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp4_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

# Create trigger which removes pool specific options upon removal of
# the pool.
DELIMITER $$
CREATE TRIGGER dhcp4_pool_BDEL BEFORE DELETE ON dhcp4_pool FOR EACH ROW
-- Edit trigger body code below this line. Do not edit lines above this one
BEGIN
DELETE FROM dhcp4_options WHERE scope_id = 5 AND pool_id = OLD.id;
END
$$
DELIMITER ;

-- -----------------------------------------------------
-- Table `dhcp6_server`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_server (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    tag VARCHAR(256) NOT NULL,
    description TEXT,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY dhcp6_server_tag_UNIQUE (tag),
    KEY key_dhcp6_server_modification_ts (modification_ts)
) ENGINE=InnoDB;

# Special server entry meaning "all servers". This refers to
# the configuration entries owned by all servers.
INSERT INTO dhcp6_server(id, tag, description, modification_ts)
    VALUES(1, "all", "special type: all servers", NOW());

-- -----------------------------------------------------
-- Table `dhcp6_audit`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_audit (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    object_type VARCHAR(256) NOT NULL,
    object_id BIGINT(20) UNSIGNED NOT NULL,
    modification_type TINYINT(1) NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    log_message TEXT,
    PRIMARY KEY (id),
    KEY key_dhcp6_audit_modification_ts (modification_ts),
    KEY fk_dhcp6_audit_modification_type (modification_type),
    CONSTRAINT fk_dhcp6_audit_modification_type FOREIGN KEY (modification_type)
        REFERENCES modification (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_global_parameter`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_global_parameter (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(128) NOT NULL,
    value LONGTEXT NOT NULL,
    modification_ts timestamp NOT NULL,
    PRIMARY KEY (id),
    KEY key_dhcp6_global_parameter_modification_ts (modification_ts),
    KEY key_dhcp6_global_parameter_name (name)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_global_parameter_server`
-- M-to-M cross-reference between global parameters and
-- servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_global_parameter_server (
    parameter_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (parameter_id, server_id),
    KEY fk_dhcp6_global_parameter_server_server_id (server_id),
    KEY key_dhcp6_global_parameter_server (modification_ts),
    CONSTRAINT fk_dhcp6_global_parameter_server_parameter_id FOREIGN KEY (parameter_id)
        REFERENCES dhcp6_global_parameter (id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp6_global_parameter_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp6_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_option_def`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_option_def (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    code SMALLINT UNSIGNED NOT NULL,
    name VARCHAR(128) NOT NULL,
    space VARCHAR(128) NOT NULL,
    type TINYINT UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    is_array TINYINT(1) NOT NULL,
    encapsulate VARCHAR(128) NOT NULL,
    record_types VARCHAR(512) DEFAULT NULL,
    user_context LONGTEXT,
    PRIMARY KEY (id),
    KEY key_dhcp6_option_def_modification_ts (modification_ts),
    KEY key_dhcp6_option_def_code_space (code, space)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_option_def_server`
-- M-to-M cross-reference between option definitions and
-- servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_option_def_server (
    option_def_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (option_def_id, server_id),
    KEY fk_dhcp6_option_def_server_server_id_idx (server_id),
    KEY key_dhcp6_option_def_server_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp6_option_def_server_option_def_id FOREIGN KEY (option_def_id)
        REFERENCES dhcp6_option_def (id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp6_option_def_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp6_server (id) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_shared_network`
-- -----------------------------------------------------
CREATE TABLE dhcp6_shared_network (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(128) NOT NULL,
    client_class VARCHAR(128) DEFAULT NULL,
    interface VARCHAR(128) DEFAULT NULL,
    modification_ts TIMESTAMP NOT NULL,
    preferred_lifetime INT(10) DEFAULT NULL,
    rapid_commit TINYINT(1) NOT NULL DEFAULT '1',
    rebind_timer INT(10) DEFAULT NULL,
    relay LONGTEXT DEFAULT NULL,
    renew_timer INT(10) DEFAULT NULL,
    require_client_classes LONGTEXT,
    reservation_mode TINYINT(3) NOT NULL DEFAULT '3',
    user_context LONGTEXT,
    valid_lifetime INT(10) DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY name_UNIQUE (name),
    KEY key_dhcp6_shared_network_modification_ts (modification_ts)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_shared_network_server`
-- M-to-M cross-reference between shared networks and
-- servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_shared_network_server (
    shared_network_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    KEY key_dhcp6_shared_network_server_modification_ts (modification_ts),
    KEY fk_dhcp6_shared_network_server_server_id_idx (server_id),
    KEY fk_dhcp6_shared_network_server_shared_network_id (shared_network_id),
    CONSTRAINT fk_dhcp6_shared_network_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp6_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp6_shared_network_server_shared_network_id FOREIGN KEY (shared_network_id)
        REFERENCES dhcp6_shared_network (id)
        ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_subnet`
-- -----------------------------------------------------
CREATE TABLE dhcp6_subnet (
    subnet_id INT(10) UNSIGNED NOT NULL,
    subnet_prefix VARCHAR(64) NOT NULL,
    client_class VARCHAR(128) DEFAULT NULL,
    interface VARCHAR(128) DEFAULT NULL,
    modification_ts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    preferred_lifetime INT(10) DEFAULT NULL,
    rapid_commit TINYINT(1) NOT NULL DEFAULT '1',
    rebind_timer INT(10) DEFAULT NULL,
    relay LONGTEXT DEFAULT NULL,
    renew_timer INT(10) DEFAULT NULL,
    require_client_classes LONGTEXT,
    reservation_mode TINYINT(3) NOT NULL DEFAULT '3',
    shared_network_name VARCHAR(128) DEFAULT NULL,
    user_context LONGTEXT,
    valid_lifetime INT(10) DEFAULT NULL,
    PRIMARY KEY (subnet_id),
    UNIQUE KEY subnet_prefix_UNIQUE (subnet_prefix),
    KEY subnet6_subnet_prefix (subnet_prefix),
    KEY fk_dhcp6_subnet_shared_network (shared_network_name),
    KEY key_dhcp6_subnet_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp6_subnet_shared_network FOREIGN KEY (shared_network_name)
        REFERENCES dhcp6_shared_network (name)
        ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_subnet_server`
-- M-to-M cross-reference between subnets and servers
-- -----------------------------------------------------
CREATE TABLE dhcp6_subnet_server (
    subnet_id INT(10) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (subnet_id, server_id),
    KEY fk_dhcp6_subnet_server_server_id (server_id),
    KEY key_dhcp6_subnet_server_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp6_subnet_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp6_server (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp6_subnet_server_subnet_id FOREIGN KEY (subnet_id)
        REFERENCES dhcp6_subnet (subnet_id)
        ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_pd_pool`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_pd_pool (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    prefix VARCHAR(45) NOT NULL,
    prefix_length TINYINT(3) NOT NULL,
    delegated_prefix_length TINYINT(3) NOT NULL,
    dhcp6_subnet_id INT(10) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (id),
    KEY fk_dhcp6_pd_pool_subnet_id (dhcp6_subnet_id),
    KEY key_dhcp6_pd_pool_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp6_pd_pool_subnet_id FOREIGN KEY (dhcp6_subnet_id)
        REFERENCES dhcp6_subnet (subnet_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Table `dhcp6_pool`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_pool (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    start_address VARCHAR(45) NOT NULL,
    end_address VARCHAR(45) NOT NULL,
    dhcp6_subnet_id INT(10) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (id),
    KEY fk_dhcp6_pool_subnet_id (dhcp6_subnet_id),
    KEY key_dhcp6_pool_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp6_pool_subnet_id FOREIGN KEY (dhcp6_subnet_id)
        REFERENCES dhcp6_subnet (subnet_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

# Modify the primary key to BINGINT as other tables have.
ALTER TABLE dhcp6_options MODIFY option_id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT;

# Add conifguration backend specific columns.
ALTER TABLE dhcp6_options
    ADD COLUMN shared_network_name VARCHAR(128) DEFAULT NULL,
    ADD COLUMN pool_id BIGINT(20) UNSIGNED DEFAULT NULL,
    ADD COLUMN pd_pool_id BIGINT(20) UNSIGNED DEFAULT NULL,
    ADD COLUMN modification_ts TIMESTAMP NOT NULL;

-- -----------------------------------------------------
-- Table `dhcp6_options_server`
-- M-to-M cross-reference between options and servers
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_options_server (
    option_id BIGINT(20) UNSIGNED NOT NULL,
    server_id BIGINT(20) UNSIGNED NOT NULL,
    modification_ts TIMESTAMP NOT NULL,
    PRIMARY KEY (option_id, server_id),
    KEY fk_dhcp6_options_server_server_id_idx (server_id),
    KEY key_dhcp6_options_server_modification_ts (modification_ts),
    CONSTRAINT fk_dhcp6_options_server_option_id FOREIGN KEY (option_id)
        REFERENCES dhcp6_options (option_id)
        ON DELETE NO ACTION ON UPDATE NO ACTION,
    CONSTRAINT fk_dhcp6_options_server_server_id FOREIGN KEY (server_id)
        REFERENCES dhcp6_server (id)
        ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB;

# Create trigger which removes pool specific options upon removal of
# the pool.
DELIMITER $$
CREATE TRIGGER dhcp6_pool_BDEL BEFORE DELETE ON dhcp6_pool FOR EACH ROW
-- Edit trigger body code below this line. Do not edit lines above this one
BEGIN
DELETE FROM dhcp6_options WHERE scope_id = 5 AND pool_id = OLD.id;
END
$$
DELIMITER ;

# Update the schema version number
UPDATE schema_version
SET version = '7', minor = '0';

# This line concludes database upgrade to version 7.0.


ALTER TABLE dhcp4_options
    MODIFY COLUMN modification_ts TIMESTAMP NOT NULL
    DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE dhcp6_options
    MODIFY COLUMN modification_ts TIMESTAMP NOT NULL
    DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE dhcp4_subnet
    ADD COLUMN authoritative TINYINT(1) DEFAULT NULL,
    ADD COLUMN calculate_tee_times TINYINT(1) DEFAULT NULL,
    ADD COLUMN t1_percent FLOAT DEFAULT NULL,
    ADD COLUMN t2_percent FLOAT DEFAULT NULL;

ALTER TABLE dhcp4_subnet
    MODIFY COLUMN reservation_mode TINYINT(3) DEFAULT NULL;

ALTER TABLE dhcp4_subnet
    MODIFY COLUMN match_client_id TINYINT(1) DEFAULT NULL;

ALTER TABLE dhcp4_shared_network
    ADD COLUMN authoritative TINYINT(1) DEFAULT NULL,
    ADD COLUMN calculate_tee_times TINYINT(1) DEFAULT NULL,
    ADD COLUMN t1_percent FLOAT DEFAULT NULL,
    ADD COLUMN t2_percent FLOAT DEFAULT NULL,
    ADD COLUMN boot_file_name VARCHAR(512) DEFAULT NULL,
    ADD COLUMN next_server INT(10) UNSIGNED DEFAULT NULL,
    ADD COLUMN server_hostname VARCHAR(512) DEFAULT NULL;

ALTER TABLE dhcp4_shared_network
    MODIFY COLUMN reservation_mode TINYINT(3) DEFAULT NULL;

ALTER TABLE dhcp4_shared_network
    MODIFY COLUMN match_client_id TINYINT(1) DEFAULT NULL;

ALTER TABLE dhcp6_subnet
    ADD COLUMN calculate_tee_times TINYINT(1) DEFAULT NULL,
    ADD COLUMN t1_percent FLOAT DEFAULT NULL,
    ADD COLUMN t2_percent FLOAT DEFAULT NULL,
    ADD COLUMN interface_id VARBINARY(128) DEFAULT NULL;

ALTER TABLE dhcp6_subnet
    MODIFY COLUMN reservation_mode TINYINT(3) DEFAULT NULL;

ALTER TABLE dhcp6_subnet
    MODIFY COLUMN rapid_commit TINYINT(1) DEFAULT NULL;

ALTER TABLE dhcp6_shared_network
    ADD COLUMN calculate_tee_times TINYINT(1) DEFAULT NULL,
    ADD COLUMN t1_percent FLOAT DEFAULT NULL,
    ADD COLUMN t2_percent FLOAT DEFAULT NULL,
    ADD COLUMN interface_id VARBINARY(128) DEFAULT NULL;

ALTER TABLE dhcp6_shared_network
    MODIFY COLUMN reservation_mode TINYINT(3) DEFAULT NULL;

ALTER TABLE dhcp6_shared_network
    MODIFY COLUMN rapid_commit TINYINT(1) DEFAULT NULL;

-- -----------------------------------------------------
-- Make sure that constraints on the 7.0 schema tables
-- have appropriate referential actions. All tables
-- which join the configuration elements with the
-- servers should perform cascade deletion.
-- -----------------------------------------------------

ALTER TABLE dhcp4_global_parameter_server
    DROP FOREIGN KEY fk_dhcp4_global_parameter_server_server_id;

ALTER TABLE dhcp4_global_parameter_server
    ADD CONSTRAINT fk_dhcp4_global_parameter_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp4_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp4_option_def_server
    DROP FOREIGN KEY fk_dhcp4_option_def_server_server_id;

ALTER TABLE dhcp4_option_def_server
    ADD CONSTRAINT fk_dhcp4_option_def_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp4_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp4_shared_network_server
    DROP FOREIGN KEY fk_dhcp4_shared_network_server_server_id;

ALTER TABLE dhcp4_shared_network_server
    ADD CONSTRAINT fk_dhcp4_shared_network_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp4_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp4_subnet_server
    DROP FOREIGN KEY fk_dhcp4_subnet_server_server_id;

ALTER TABLE dhcp4_subnet_server
    ADD CONSTRAINT fk_dhcp4_subnet_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp4_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp4_options_server
    DROP FOREIGN KEY fk_dhcp4_options_server_server_id;

ALTER TABLE dhcp4_options_server
    ADD CONSTRAINT fk_dhcp4_options_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp4_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp6_global_parameter_server
    DROP FOREIGN KEY fk_dhcp6_global_parameter_server_server_id;

ALTER TABLE dhcp6_global_parameter_server
    ADD CONSTRAINT fk_dhcp6_global_parameter_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp6_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp6_option_def_server
    DROP FOREIGN KEY fk_dhcp6_option_def_server_server_id;

ALTER TABLE dhcp6_option_def_server
    ADD CONSTRAINT fk_dhcp6_option_def_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp6_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp6_shared_network_server
    DROP FOREIGN KEY fk_dhcp6_shared_network_server_server_id;

ALTER TABLE dhcp6_shared_network_server
    ADD CONSTRAINT fk_dhcp6_shared_network_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp6_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp6_subnet_server
    DROP FOREIGN KEY fk_dhcp6_subnet_server_server_id;

ALTER TABLE dhcp6_subnet_server
    ADD CONSTRAINT fk_dhcp6_subnet_server_server_id
        FOREIGN KEY (server_id)
    REFERENCES dhcp6_server (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

ALTER TABLE dhcp6_options_server
    DROP FOREIGN KEY fk_dhcp6_options_server_option_id;

ALTER TABLE dhcp6_options_server
    ADD CONSTRAINT fk_dhcp6_options_server_option_id
        FOREIGN KEY (option_id)
    REFERENCES dhcp6_options (option_id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

-- -----------------------------------------------------
-- Table `dhcp4_audit_revision`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp4_audit_revision (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    modification_ts TIMESTAMP NOT NULL,
    log_message TEXT,
    server_id BIGINT(10) UNSIGNED,
    PRIMARY KEY (id),
    KEY key_dhcp4_audit_revision_by_modification_ts (modification_ts)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Drop columns from the dhcp4_audit table which now
-- belong to the dhcp4_audit_revision.
-- -----------------------------------------------------
ALTER TABLE dhcp4_audit
    DROP COLUMN modification_ts,
    DROP COLUMN log_message;

-- -----------------------------------------------------
-- Add column revision_id and the foreign key with a
-- reference to the dhcp4_audit_revision table.
-- -----------------------------------------------------
ALTER TABLE dhcp4_audit
    ADD COLUMN revision_id BIGINT(20) UNSIGNED NOT NULL;

ALTER TABLE dhcp4_audit
    ADD CONSTRAINT fk_dhcp4_audit_revision FOREIGN KEY (revision_id)
        REFERENCES dhcp4_audit_revision (id)
        ON DELETE NO ACTION ON UPDATE CASCADE;

-- -----------------------------------------------------
-- Stored procedure which creates a new entry in the
-- dhcp4_audit_revision table and sets appropriate session
-- variables to be used while creating the audit entries
-- by triggers. This procedure should be called at the
-- beginning of a transaction which modifies configuration
-- data in the database, e.g. when new subnet is added.
--
-- Parameters:
-- - audit_ts timestamp to be associated with the audit
--   revision.
-- - server_tag is used to retrieve the server_id which
--   associates the changes applied with the particular
--   server or all servers.
-- - audit_log_message is a log message associates with
--   the audit revision.
-- - cascade_transaction is assigned to a session
--   variable which is used in some triggers to determine
--   if the audit entry should be created for them or
--   not. Specifically, this is used when DHCP options
--   are inserted, updated or deleted. If such modification
--   is a part of the larger change (e.g. change in the
--   subnet the options belong to) the dedicated audit
--   entry for options must not be created. On the other
--   hand, if the global option is being added, the
--   audit entry for the option must be created because
--   it is the sole object modified in that case.
--   Session variable disable_audit is used to disable
--   the procedure when wiping the database during
--   unit tests.  This avoids issues with revision_id
--   being null.
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS createAuditRevisionDHCP4;
DELIMITER $$
CREATE PROCEDURE createAuditRevisionDHCP4(IN audit_ts TIMESTAMP,
                                          IN server_tag VARCHAR(256),
                                          IN audit_log_message TEXT,
                                          IN cascade_transaction TINYINT(1))
BEGIN
    DECLARE srv_id BIGINT(20);
    IF @disable_audit IS NULL OR @disable_audit = 0 THEN
        SELECT id INTO srv_id FROM dhcp4_server WHERE tag = server_tag;
        INSERT INTO dhcp4_audit_revision (modification_ts, server_id, log_message)
            VALUES (audit_ts, srv_id, audit_log_message);
        SET @audit_revision_id = LAST_INSERT_ID();
        SET @cascade_transaction = cascade_transaction;
    END IF;
END $$
DELIMITER ;

-- -----------------------------------------------------
-- Stored procedure which creates a new entry in the
-- dhcp4_audit table. It should be called from the
-- triggers of the tables where the config modifications
-- are applied. The @audit_revision_id variable contains
-- the revision id to be placed in the audit entries.
--
-- The following parameters are passed to this procedure:
-- - object_type_val: name of the table to be associated
--   with the applied changes.
-- - object_id_val: identifier of the modified object in
--   that table.
-- - modification_type_val: string value indicating the
--   type of the change, i.e. "create", "update" or
--   "delete".
--   Session variable disable_audit is used to disable
--   the procedure when wiping the database during
--   unit tests.  This avoids issues with revision_id
--   being null.
-- ----------------------------------------------------
DROP PROCEDURE IF EXISTS createAuditEntryDHCP4;
DELIMITER $$
CREATE PROCEDURE createAuditEntryDHCP4(IN object_type_val VARCHAR(256),
                                       IN object_id_val BIGINT(20) UNSIGNED,
                                       IN modification_type_val VARCHAR(32))
BEGIN
    IF @disable_audit IS NULL OR @disable_audit = 0 THEN
        INSERT INTO dhcp4_audit (object_type, object_id, modification_type, revision_id)
            VALUES (object_type_val, object_id_val, \
               (SELECT id FROM modification WHERE modification_type = modification_type_val), \
                @audit_revision_id);
    END IF;
END $$
DELIMITER ;

-- -----------------------------------------------------
-- Triggers used to create entries in the audit
-- tables upon insertion, update or deletion of the
-- configuration entries.
-- -----------------------------------------------------

# Create dhcp4_global_parameter insert trigger
DELIMITER $$
CREATE TRIGGER dhcp4_global_parameter_AINS AFTER INSERT ON dhcp4_global_parameter
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_global_parameter', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp4_global_parameter update trigger
DELIMITER $$
CREATE TRIGGER dhcp4_global_parameter_AUPD AFTER UPDATE ON dhcp4_global_parameter
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_global_parameter', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp4_global_parameter delete trigger
DELIMITER $$
CREATE TRIGGER dhcp4_global_parameter_ADEL AFTER DELETE ON dhcp4_global_parameter
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_global_parameter', OLD.id, "delete");
    END $$
DELIMITER ;

# Create dhcp4_subnet insert trigger
DELIMITER $$
CREATE TRIGGER dhcp4_subnet_AINS AFTER INSERT ON dhcp4_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_subnet', NEW.subnet_id, "create");
    END $$
DELIMITER ;

# Create dhcp4_subnet update trigger
DELIMITER $$
CREATE TRIGGER dhcp4_subnet_AUPD AFTER UPDATE ON dhcp4_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_subnet', NEW.subnet_id, "update");
    END $$
DELIMITER ;

# Create dhcp4_subnet delete trigger
DELIMITER $$
CREATE TRIGGER dhcp4_subnet_ADEL AFTER DELETE ON dhcp4_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_subnet', OLD.subnet_id, "delete");
    END $$
DELIMITER ;

# Create dhcp4_shared_network insert trigger
DELIMITER $$
CREATE TRIGGER dhcp4_shared_network_AINS AFTER INSERT ON dhcp4_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_shared_network', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp4_shared_network update trigger
DELIMITER $$
CREATE TRIGGER dhcp4_shared_network_AUPD AFTER UPDATE ON dhcp4_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_shared_network', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp4_shared_network delete trigger
DELIMITER $$
CREATE TRIGGER dhcp4_shared_network_ADEL AFTER DELETE ON dhcp4_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_shared_network', OLD.id, "delete");
    END $$
DELIMITER ;

# Create dhcp4_option_def insert trigger
DELIMITER $$
CREATE TRIGGER dhcp4_option_def_AINS AFTER INSERT ON dhcp4_option_def
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_option_def', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp4_option_def update trigger
DELIMITER $$
CREATE TRIGGER dhcp4_option_def_AUPD AFTER UPDATE ON dhcp4_option_def
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_option_def', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp4_option_def delete trigger
DELIMITER $$
CREATE TRIGGER dhcp4_option_def_ADEL AFTER DELETE ON dhcp4_option_def
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_option_def', OLD.id, "delete");
    END $$
DELIMITER ;

-- -----------------------------------------------------
-- Stored procedure which creates an audit entry for a
-- DHCPv4 option. Depending on the scope of the option
-- the audit entry can be created for various levels
-- of configuration hierarchy. If this is a global
-- option the audit entry is created for this option
-- for CREATE, UPDATE or DELETE. If the option is being
-- added for an owning option, e.g. for a subnet, the
-- audit entry is created as an UPDATE to this object.
-- From the Kea perspective such option addition will
-- be seen as a subnet update and the server will fetch
-- the whole subnet and merge it into its configuration.
-- The audit entry is not created if it was already
-- created as part of the current transaction.
--
-- The following parameters are passed to the procedure:
-- - modification_type: "create", "update" or "delete"
-- - scope_id: identifier of the option scope, e.g.
--   global, subnet specific etc. See dhcp_option_scope
--   for specific values.
-- - option_id: identifier of the option.
-- - subnet_id: identifier of the subnet if the option
--   belongs to the subnet.
-- - host_id: identifier of the host if the option
-- - belongs to the host.
-- - network_name: shared network name if the option
--   belongs to the shared network.
-- - pool_id: identifier of the pool if the option
--   belongs to the pool.
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS createOptionAuditDHCP4;
DELIMITER $$
CREATE PROCEDURE createOptionAuditDHCP4(IN modification_type VARCHAR(32),
                                        IN scope_id TINYINT(3) UNSIGNED,
                                        IN option_id BIGINT(20) UNSIGNED,
                                        IN subnet_id INT(10) UNSIGNED,
                                        IN host_id INT(10) UNSIGNED,
                                        IN network_name VARCHAR(128),
                                        IN pool_id BIGINT(20))
BEGIN
    # These variables will hold shared network id and subnet id that
    # we will select.
    DECLARE snid VARCHAR(128);
    DECLARE sid INT(10) UNSIGNED;

    # Cascade transaction flag is set to 1 to prevent creation of
    # the audit entries for the options when the options are
    # created as part of the parent object creation or update.
    # For example: when the option is added as part of the subnet
    # addition, the cascade transaction flag is equal to 1. If
    # the option is added into the existing subnet the cascade
    # transaction is equal to 0. Note that depending on the option
    # scope the audit entry will contain the object_type value
    # of the parent object to cause the server to replace the
    # entire subnet. The only case when the object_type will be
    # set to 'dhcp4_options' is when a global option is added.
    # Global options do not have the owner.
    IF @cascade_transaction IS NULL OR @cascade_transaction = 0 THEN
        # todo: host manager hasn't been updated to use audit
        # mechanisms so ignore host specific options for now.
        IF scope_id = 0 THEN
            # If a global option is added or modified, create audit
            # entry for the 'dhcp4_options' table.
            CALL createAuditEntryDHCP4('dhcp4_options', option_id, modification_type);
        ELSEIF scope_id = 1 THEN
            # If subnet specific option is added or modified, create
            # audit entry for the entire subnet, which indicates that
            # it should be treated as the subnet update.
            CALL createAuditEntryDHCP4('dhcp4_subnet', subnet_id, "update");
        ELSEIF scope_id = 4 THEN
            # If shared network specific option is added or modified,
            # create audit entry for the shared network which
            # indicates that it should be treated as the shared
            # network update.
           SELECT id INTO snid FROM dhcp4_shared_network WHERE name = network_name LIMIT 1;
           CALL createAuditEntryDHCP4('dhcp4_shared_network', snid, "update");
        ELSEIF scope_id = 5 THEN
            # If pool specific option is added or modified, create
            # audit entry for the subnet which this pool belongs to.
            SELECT dhcp4_pool.subnet_id INTO sid FROM dhcp4_pool WHERE id = pool_id;
            CALL createAuditEntryDHCP4('dhcp4_subnet', sid, "update");
        END IF;
    END IF;
END $$
DELIMITER ;

# Create dhcp4_options insert trigger
DELIMITER $$
CREATE TRIGGER dhcp4_options_AINS AFTER INSERT ON dhcp4_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP4("create", NEW.scope_id, NEW.option_id, NEW.dhcp4_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id);
    END $$
DELIMITER ;

# Create dhcp4_options update trigger
DELIMITER $$
CREATE TRIGGER dhcp4_options_AUPD AFTER UPDATE ON dhcp4_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP4("update", NEW.scope_id, NEW.option_id, NEW.dhcp4_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id);
    END $$
DELIMITER ;

# Create dhcp4_options delete trigger
DELIMITER $$
CREATE TRIGGER dhcp4_options_ADEL AFTER DELETE ON dhcp4_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP4("delete", OLD.scope_id, OLD.option_id, OLD.dhcp4_subnet_id,
                                    OLD.host_id, OLD.shared_network_name, OLD.pool_id);
    END $$
DELIMITER ;

-- -----------------------------------------------------
-- Table `parameter_data_type`
-- Reflects an enum used by Kea to define supported
-- data types for the simple configuration parameters,
-- e.g. global parameters used by DHCP servers.
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS parameter_data_type (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    name VARCHAR(32) NOT NULL
) ENGINE = InnoDB;

START TRANSACTION;
INSERT INTO parameter_data_type VALUES (0, 'integer');
INSERT INTO parameter_data_type VALUES (1, 'real');
INSERT INTO parameter_data_type VALUES (2, 'boolean');
INSERT INTO parameter_data_type VALUES (4, 'string');
COMMIT;

ALTER TABLE dhcp4_global_parameter
    ADD COLUMN parameter_type TINYINT UNSIGNED NOT NULL;

ALTER TABLE dhcp4_global_parameter
    ADD CONSTRAINT fk_dhcp4_global_parameter_type FOREIGN KEY (parameter_type)
        REFERENCES parameter_data_type (id);

ALTER TABLE dhcp6_global_parameter
    ADD COLUMN parameter_type TINYINT UNSIGNED NOT NULL;

ALTER TABLE dhcp6_global_parameter
    ADD CONSTRAINT fk_dhcp6_global_parameter_type FOREIGN KEY (parameter_type)
        REFERENCES parameter_data_type (id);


-- Rename dhcp6_subnet_id column of dhcp6_pool and dhcp6_pd_pool

ALTER TABLE dhcp6_pool
    DROP FOREIGN KEY fk_dhcp6_pool_subnet_id;
DROP INDEX fk_dhcp6_pool_subnet_id
    ON dhcp6_pool;

ALTER TABLE dhcp6_pd_pool
    DROP FOREIGN KEY fk_dhcp6_pd_pool_subnet_id;
DROP INDEX fk_dhcp6_pd_pool_subnet_id
    ON dhcp6_pd_pool;

ALTER TABLE dhcp6_pool
    CHANGE dhcp6_subnet_id subnet_id INT(10) UNSIGNED NOT NULL;

ALTER TABLE dhcp6_pd_pool
    CHANGE dhcp6_subnet_id subnet_id INT(10) UNSIGNED NOT NULL;

ALTER TABLE dhcp6_pool
    ADD CONSTRAINT fk_dhcp6_pool_subnet_id
    FOREIGN KEY (subnet_id)
    REFERENCES dhcp6_subnet (subnet_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE dhcp6_pd_pool
    ADD CONSTRAINT fk_dhcp6_pd_pool_subnet_id
    FOREIGN KEY (subnet_id)
    REFERENCES dhcp6_subnet (subnet_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

-- align dhcp6_shared_network_server indexes on dhcp4_shared_network_server

ALTER TABLE dhcp6_shared_network_server
    ADD PRIMARY KEY (shared_network_id, server_id);

ALTER TABLE dhcp6_shared_network_server
    DROP FOREIGN KEY fk_dhcp6_shared_network_server_shared_network_id;
DROP INDEX fk_dhcp6_shared_network_server_shared_network_id
    ON dhcp6_shared_network_server;
ALTER TABLE dhcp6_shared_network_server
    ADD CONSTRAINT fk_dhcp6_shared_network_server_shared_network_id
    FOREIGN KEY (shared_network_id)
    REFERENCES dhcp6_shared_network (id)
    ON DELETE CASCADE ON UPDATE NO ACTION;

-- Update dhcp4_subnet_server and dhcp6_subnet_server to allow update
-- on the prefix too by setting the CASCADE action.

ALTER TABLE dhcp4_subnet_server
    DROP FOREIGN KEY fk_dhcp4_subnet_server_subnet_id;
ALTER TABLE dhcp4_subnet_server
    ADD CONSTRAINT fk_dhcp4_subnet_server_subnet_id FOREIGN KEY (subnet_id)
    REFERENCES dhcp4_subnet (subnet_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE dhcp6_subnet_server
    DROP FOREIGN KEY fk_dhcp6_subnet_server_subnet_id;
ALTER TABLE dhcp6_subnet_server
    ADD CONSTRAINT fk_dhcp6_subnet_server_subnet_id FOREIGN KEY (subnet_id)
    REFERENCES dhcp6_subnet (subnet_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

-- -----------------------------------------------------
-- Table `dhcp6_audit_revision`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp6_audit_revision (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    modification_ts TIMESTAMP NOT NULL,
    log_message TEXT,
    server_id BIGINT(10) UNSIGNED,
    PRIMARY KEY (id),
    KEY key_dhcp6_audit_revision_by_modification_ts (modification_ts)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Drop columns from the dhcp6_audit table which now
-- belong to the dhcp6_audit_revision.
-- -----------------------------------------------------
ALTER TABLE dhcp6_audit
    DROP COLUMN modification_ts,
    DROP COLUMN log_message;

-- -----------------------------------------------------
-- Add column revision_id and the foreign key with a
-- reference to the dhcp6_audit_revision table.
-- -----------------------------------------------------
ALTER TABLE dhcp6_audit
    ADD COLUMN revision_id BIGINT(20) UNSIGNED NOT NULL;

ALTER TABLE dhcp6_audit
    ADD CONSTRAINT fk_dhcp6_audit_revision FOREIGN KEY (revision_id)
        REFERENCES dhcp6_audit_revision (id)
        ON DELETE NO ACTION ON UPDATE CASCADE;

-- -----------------------------------------------------
-- Stored procedure which creates a new entry in the
-- dhcp6_audit_revision table and sets appropriate session
-- variables to be used while creating the audit entries
-- by triggers. This procedure should be called at the
-- beginning of a transaction which modifies configuration
-- data in the database, e.g. when new subnet is added.
--
-- Parameters:
-- - audit_ts timestamp to be associated with the audit
--   revision.
-- - server_tag is used to retrieve the server_id which
--   associates the changes applied with the particular
--   server or all servers.
-- - audit_log_message is a log message associates with
--   the audit revision.
-- - cascade_transaction is assigned to a session
--   variable which is used in some triggers to determine
--   if the audit entry should be created for them or
--   not. Specifically, this is used when DHCP options
--   are inserted, updated or deleted. If such modification
--   is a part of the larger change (e.g. change in the
--   subnet the options belong to) the dedicated audit
--   entry for options must not be created. On the other
--   hand, if the global option is being added, the
--   audit entry for the option must be created because
--   it is the sole object modified in that case.
--   Session variable disable_audit is used to disable
--   the procedure when wiping the database during
--   unit tests.  This avoids issues with revision_id
--   being null.
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS createAuditRevisionDHCP6;
DELIMITER $$
CREATE PROCEDURE createAuditRevisionDHCP6(IN audit_ts TIMESTAMP,
                                          IN server_tag VARCHAR(256),
                                          IN audit_log_message TEXT,
                                          IN cascade_transaction TINYINT(1))
BEGIN
    DECLARE srv_id BIGINT(20);
    IF @disable_audit IS NULL OR @disable_audit = 0 THEN
        SELECT id INTO srv_id FROM dhcp6_server WHERE tag = server_tag;
        INSERT INTO dhcp6_audit_revision (modification_ts, server_id, log_message)
            VALUES (audit_ts, srv_id, audit_log_message);
        SET @audit_revision_id = LAST_INSERT_ID();
        SET @cascade_transaction = cascade_transaction;
    END IF;
END $$
DELIMITER ;

-- -----------------------------------------------------
-- Stored procedure which creates a new entry in the
-- dhcp6_audit table. It should be called from the
-- triggers of the tables where the config modifications
-- are applied. The @audit_revision_id variable contains
-- the revision id to be placed in the audit entries.
--
-- The following parameters are passed to this procedure:
-- - object_type_val: name of the table to be associated
--   with the applied changes.
-- - object_id_val: identifier of the modified object in
--   that table.
-- - modification_type_val: string value indicating the
--   type of the change, i.e. "create", "update" or
--   "delete".
--   Session variable disable_audit is used to disable
--   the procedure when wiping the database during
--   unit tests.  This avoids issues with revision_id
--   being null.
-- ----------------------------------------------------
DROP PROCEDURE IF EXISTS createAuditEntryDHCP6;
DELIMITER $$
CREATE PROCEDURE createAuditEntryDHCP6(IN object_type_val VARCHAR(256),
                                       IN object_id_val BIGINT(20) UNSIGNED,
                                       IN modification_type_val VARCHAR(32))
BEGIN
    IF @disable_audit IS NULL OR @disable_audit = 0 THEN
        INSERT INTO dhcp6_audit (object_type, object_id, modification_type, revision_id)
            VALUES (object_type_val, object_id_val, \
               (SELECT id FROM modification WHERE modification_type = modification_type_val), \
                @audit_revision_id);
    END IF;
END $$
DELIMITER ;

-- -----------------------------------------------------
-- Triggers used to create entries in the audit
-- tables upon insertion, update or deletion of the
-- configuration entries.
-- -----------------------------------------------------

# Create dhcp6_global_parameter insert trigger
DELIMITER $$
CREATE TRIGGER dhcp6_global_parameter_AINS AFTER INSERT ON dhcp6_global_parameter
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_global_parameter', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp6_global_parameter update trigger
DELIMITER $$
CREATE TRIGGER dhcp6_global_parameter_AUPD AFTER UPDATE ON dhcp6_global_parameter
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_global_parameter', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp6_global_parameter delete trigger
DELIMITER $$
CREATE TRIGGER dhcp6_global_parameter_ADEL AFTER DELETE ON dhcp6_global_parameter
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_global_parameter', OLD.id, "delete");
    END $$
DELIMITER ;

# Create dhcp6_subnet insert trigger
DELIMITER $$
CREATE TRIGGER dhcp6_subnet_AINS AFTER INSERT ON dhcp6_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_subnet', NEW.subnet_id, "create");
    END $$
DELIMITER ;

# Create dhcp6_subnet update trigger
DELIMITER $$
CREATE TRIGGER dhcp6_subnet_AUPD AFTER UPDATE ON dhcp6_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_subnet', NEW.subnet_id, "update");
    END $$
DELIMITER ;

# Create dhcp6_subnet delete trigger
DELIMITER $$
CREATE TRIGGER dhcp6_subnet_ADEL AFTER DELETE ON dhcp6_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_subnet', OLD.subnet_id, "delete");
    END $$
DELIMITER ;

# Create dhcp6_shared_network insert trigger
DELIMITER $$
CREATE TRIGGER dhcp6_shared_network_AINS AFTER INSERT ON dhcp6_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_shared_network', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp6_shared_network update trigger
DELIMITER $$
CREATE TRIGGER dhcp6_shared_network_AUPD AFTER UPDATE ON dhcp6_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_shared_network', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp6_shared_network delete trigger
DELIMITER $$
CREATE TRIGGER dhcp6_shared_network_ADEL AFTER DELETE ON dhcp6_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_shared_network', OLD.id, "delete");
    END $$
DELIMITER ;

# Create dhcp6_option_def insert trigger
DELIMITER $$
CREATE TRIGGER dhcp6_option_def_AINS AFTER INSERT ON dhcp6_option_def
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_option_def', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp6_option_def update trigger
DELIMITER $$
CREATE TRIGGER dhcp6_option_def_AUPD AFTER UPDATE ON dhcp6_option_def
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_option_def', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp6_option_def delete trigger
DELIMITER $$
CREATE TRIGGER dhcp6_option_def_ADEL AFTER DELETE ON dhcp6_option_def
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_option_def', OLD.id, "delete");
    END $$
DELIMITER ;

-- -----------------------------------------------------
-- Stored procedure which creates an audit entry for a
-- DHCPv6 option. Depending on the scope of the option
-- the audit entry can be created for various levels
-- of configuration hierarchy. If this is a global
-- option the audit entry is created for this option
-- for CREATE, UPDATE or DELETE. If the option is being
-- added for an owning option, e.g. for a subnet, the
-- audit entry is created as an UPDATE to this object.
-- From the Kea perspective such option addition will
-- be seen as a subnet update and the server will fetch
-- the whole subnet and merge it into its configuration.
-- The audit entry is not created if it was already
-- created as part of the current transaction.
--
-- The following parameters are passed to the procedure:
-- - modification_type: "create", "update" or "delete"
-- - scope_id: identifier of the option scope, e.g.
--   global, subnet specific etc.
-- - option_id: identifier of the option.
-- - subnet_id: identifier of the subnet if the option
--   belongs to the subnet.
-- - host_id: identifier of the host if the option
-- - belongs to the host.
-- - network_name: shared network name if the option
--   belongs to the shared network.
-- - pool_id: identifier of the pool if the option
--   belongs to the pool.
-- - pd_pool_id: identifier of the pool if the option
--   belongs to the pd pool.
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS createOptionAuditDHCP6;
DELIMITER $$
CREATE PROCEDURE createOptionAuditDHCP6(IN modification_type VARCHAR(32),
                                        IN scope_id TINYINT(3) UNSIGNED,
                                        IN option_id BIGINT(20) UNSIGNED,
                                        IN subnet_id INT(10) UNSIGNED,
                                        IN host_id INT(10) UNSIGNED,
                                        IN network_name VARCHAR(128),
                                        IN pool_id BIGINT(20),
                                        IN pd_pool_id BIGINT(20))
BEGIN
    # These variables will hold shared network id and subnet id that
    # we will select.
    DECLARE snid VARCHAR(128);
    DECLARE sid INT(10) UNSIGNED;

    # Cascade transaction flag is set to 1 to prevent creation of
    # the audit entries for the options when the options are
    # created as part of the parent object creation or update.
    # For example: when the option is added as part of the subnet
    # addition, the cascade transaction flag is equal to 1. If
    # the option is added into the existing subnet the cascade
    # transaction is equal to 0. Note that depending on the option
    # scope the audit entry will contain the object_type value
    # of the parent object to cause the server to replace the
    # entire subnet. The only case when the object_type will be
    # set to 'dhcp6_options' is when a global option is added.
    # Global options do not have the owner.
    IF @cascade_transaction IS NULL OR @cascade_transaction = 0 THEN
        # todo: host manager hasn't been updated to use audit
        # mechanisms so ignore host specific options for now.
        IF scope_id = 0 THEN
            # If a global option is added or modified, create audit
            # entry for the 'dhcp6_options' table.
            CALL createAuditEntryDHCP6('dhcp6_options', option_id, modification_type);
        ELSEIF scope_id = 1 THEN
            # If subnet specific option is added or modified, create
            # audit entry for the entire subnet, which indicates that
            # it should be treated as the subnet update.
            CALL createAuditEntryDHCP6('dhcp6_subnet', subnet_id, "update");
        ELSEIF scope_id = 4 THEN
            # If shared network specific option is added or modified,
            # create audit entry for the shared network which
            # indicates that it should be treated as the shared
            # network update.
           SELECT id INTO snid FROM dhcp6_shared_network WHERE name = network_name LIMIT 1;
           CALL createAuditEntryDHCP6('dhcp6_shared_network', snid, "update");
        ELSEIF scope_id = 5 THEN
            # If pool specific option is added or modified, create
            # audit entry for the subnet which this pool belongs to.
            SELECT dhcp6_pool.subnet_id INTO sid FROM dhcp6_pool WHERE id = pool_id;
            CALL createAuditEntryDHCP6('dhcp6_subnet', sid, "update");
        ELSEIF scope_id = 6 THEN
            # If pd pool specific option is added or modified, create
            # audit entry for the subnet which this pd pool belongs to.
            SELECT dhcp6_pd_pool.subnet_id INTO sid FROM dhcp6_pd_pool WHERE id = pd_pool_id;
            CALL createAuditEntryDHCP6('dhcp6_subnet', sid, "update");
        END IF;
    END IF;
END $$
DELIMITER ;

# Create dhcp6_options insert trigger
DELIMITER $$
CREATE TRIGGER dhcp6_options_AINS AFTER INSERT ON dhcp6_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP6("create", NEW.scope_id, NEW.option_id, NEW.dhcp6_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id, NEW.pd_pool_id);
    END $$
DELIMITER ;

# Create dhcp6_options update trigger
DELIMITER $$
CREATE TRIGGER dhcp6_options_AUPD AFTER UPDATE ON dhcp6_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP6("update", NEW.scope_id, NEW.option_id, NEW.dhcp6_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id, NEW.pd_pool_id);
    END $$
DELIMITER ;

# Create dhcp6_options delete trigger
DELIMITER $$
CREATE TRIGGER dhcp6_options_ADEL AFTER DELETE ON dhcp6_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP6("delete", OLD.scope_id, OLD.option_id, OLD.dhcp6_subnet_id,
                                    OLD.host_id, OLD.shared_network_name, OLD.pool_id, OLD.pd_pool_id);
    END $$
DELIMITER ;

# Update the schema version number
UPDATE schema_version
SET version = '8', minor = '0';

# This line concludes database upgrade to version 8.0.

# Add lifetime bounds
ALTER TABLE dhcp4_shared_network
    ADD COLUMN min_valid_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN max_valid_lifetime INT(10) DEFAULT NULL;

ALTER TABLE dhcp4_subnet
    ADD COLUMN min_valid_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN max_valid_lifetime INT(10) DEFAULT NULL;

ALTER TABLE dhcp6_shared_network
    ADD COLUMN min_preferred_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN max_preferred_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN min_valid_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN max_valid_lifetime INT(10) DEFAULT NULL;

ALTER TABLE dhcp6_subnet
    ADD COLUMN min_preferred_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN max_preferred_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN min_valid_lifetime INT(10) DEFAULT NULL,
    ADD COLUMN max_valid_lifetime INT(10) DEFAULT NULL;

# Create dhcp4_server insert trigger
DELIMITER $$
CREATE TRIGGER dhcp4_server_AINS AFTER INSERT ON dhcp4_server
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_server', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp4_server update trigger
DELIMITER $$
CREATE TRIGGER dhcp4_server_AUPD AFTER UPDATE ON dhcp4_server
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_server', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp4_server delete trigger
DELIMITER $$
CREATE TRIGGER dhcp4_server_ADEL AFTER DELETE ON dhcp4_server
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_server', OLD.id, "delete");
    END $$
DELIMITER ;

# Create dhcp6_server insert trigger
DELIMITER $$
CREATE TRIGGER dhcp6_server_AINS AFTER INSERT ON dhcp6_server
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_server', NEW.id, "create");
    END $$
DELIMITER ;

# Create dhcp6_server update trigger
DELIMITER $$
CREATE TRIGGER dhcp6_server_AUPD AFTER UPDATE ON dhcp6_server
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_server', NEW.id, "update");
    END $$
DELIMITER ;

# Create dhcp6_server delete trigger
DELIMITER $$
CREATE TRIGGER dhcp6_server_ADEL AFTER DELETE ON dhcp6_server
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_server', OLD.id, "delete");
    END $$
DELIMITER ;

# Put the auth key in hexadecimal (double size but far more user friendly).
ALTER TABLE hosts
    MODIFY COLUMN auth_key VARCHAR(32) NULL;

# Update the schema version number
UPDATE schema_version
SET version = '8', minor = '1';

# This line concludes database upgrade to version 8.1.

# Drop existing trigger on the dhcp4_shared_network table.
DROP TRIGGER dhcp4_shared_network_ADEL;

# Create new trigger which will delete options associated with the shared
# network.
DELIMITER $$
CREATE TRIGGER dhcp4_shared_network_BDEL BEFORE DELETE ON dhcp4_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_shared_network', OLD.id, "delete");
        DELETE FROM dhcp4_options WHERE shared_network_name = OLD.name;
    END $$
DELIMITER ;

# Drop existing trigger on the dhcp4_subnet table.
DROP TRIGGER dhcp4_subnet_ADEL;

# Create new trigger which will delete pools associated with the subnet and
# the options associated with the subnet.
DELIMITER $$
CREATE TRIGGER dhcp4_subnet_BDEL BEFORE DELETE ON dhcp4_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP4('dhcp4_subnet', OLD.subnet_id, "delete");
        DELETE FROM dhcp4_pool WHERE subnet_id = OLD.subnet_id;
        DELETE FROM dhcp4_options WHERE dhcp4_subnet_id = OLD.subnet_id;
    END $$
DELIMITER ;

# Do not perform cascade deletion of the data in the dhcp4_pool because
# the cascade deletion does not execute triggers associated with the table.
# Instead we are going to use triggers on the dhcp4_subnet table.
ALTER TABLE dhcp4_pool
    DROP FOREIGN KEY fk_dhcp4_pool_subnet_id;

ALTER TABLE dhcp4_pool
    ADD CONSTRAINT fk_dhcp4_pool_subnet_id FOREIGN KEY (subnet_id)
    REFERENCES dhcp4_subnet (subnet_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

# Drop existing trigger on the dhcp6_shared_network table.
DROP TRIGGER dhcp6_shared_network_ADEL;

# Create new trigger which will delete options associated with the shared
# network.
DELIMITER $$
CREATE TRIGGER dhcp6_shared_network_BDEL BEFORE DELETE ON dhcp6_shared_network
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_shared_network', OLD.id, "delete");
        DELETE FROM dhcp6_options WHERE shared_network_name = OLD.name;
    END $$
DELIMITER ;

# Drop existing trigger on the dhcp6_subnet table.
DROP TRIGGER dhcp6_subnet_ADEL;

# Create new trigger which will delete pools associated with the subnet and
# the options associated with the subnet.
DELIMITER $$
CREATE TRIGGER dhcp6_subnet_BDEL BEFORE DELETE ON dhcp6_subnet
    FOR EACH ROW
    BEGIN
        CALL createAuditEntryDHCP6('dhcp6_subnet', OLD.subnet_id, "delete");
        DELETE FROM dhcp6_pool WHERE subnet_id = OLD.subnet_id;
        DELETE FROM dhcp6_pd_pool WHERE subnet_id = OLD.subnet_id;
        DELETE FROM dhcp6_options WHERE dhcp6_subnet_id = OLD.subnet_id;
    END $$
DELIMITER ;

# Do not perform cascade deletion of the data in the dhcp6_pool and dhcp6_pd_pool
# because the cascaded deletion does not execute triggers associated with the table.
# Instead we are going to use triggers on the dhcp6_subnet table.
ALTER TABLE dhcp6_pool
    DROP FOREIGN KEY fk_dhcp6_pool_subnet_id;

ALTER TABLE dhcp6_pd_pool
    DROP FOREIGN KEY fk_dhcp6_pd_pool_subnet_id;

ALTER TABLE dhcp6_pool
    ADD CONSTRAINT fk_dhcp6_pool_subnet_id FOREIGN KEY (subnet_id)
    REFERENCES dhcp6_subnet (subnet_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dhcp6_pd_pool
    ADD CONSTRAINT fk_dhcp6_pd_pool_subnet_id FOREIGN KEY (subnet_id)
    REFERENCES dhcp6_subnet (subnet_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

# Create trigger which removes pool specific options upon removal of
# the pool.
DELIMITER $$
CREATE TRIGGER dhcp6_pd_pool_BDEL BEFORE DELETE ON dhcp6_pd_pool FOR EACH ROW
BEGIN
DELETE FROM dhcp6_options WHERE scope_id = 6 AND pd_pool_id = OLD.id;
END
$$
DELIMITER ;

# Add missing columns in pools.
ALTER TABLE dhcp4_pool
    ADD COLUMN client_class VARCHAR(128) DEFAULT NULL,
    ADD COLUMN require_client_classes LONGTEXT,
    ADD COLUMN user_context LONGTEXT;

ALTER TABLE dhcp6_pd_pool
    ADD COLUMN excluded_prefix VARCHAR(45) DEFAULT NULL,
    ADD COLUMN excluded_prefix_length TINYINT(3) NOT NULL,
    ADD COLUMN client_class VARCHAR(128) DEFAULT NULL,
    ADD COLUMN require_client_classes LONGTEXT,
    ADD COLUMN user_context LONGTEXT;

ALTER TABLE dhcp6_pool
    ADD COLUMN client_class VARCHAR(128) DEFAULT NULL,
    ADD COLUMN require_client_classes LONGTEXT,
    ADD COLUMN user_context LONGTEXT;

-- -----------------------------------------------------
--
-- New version of the createOptionAuditDHCP4 stored
-- procedure which updates modification timestamp of
-- a parent object when an option is modified.
--
-- The following parameters are passed to the procedure:
-- - modification_type: "create", "update" or "delete"
-- - scope_id: identifier of the option scope, e.g.
--   global, subnet specific etc.
-- - option_id: identifier of the option.
-- - subnet_id: identifier of the subnet if the option
--   belongs to the subnet.
-- - host_id: identifier of the host if the option
-- - belongs to the host.
-- - network_name: shared network name if the option
--   belongs to the shared network.
-- - pool_id: identifier of the pool if the option
--   belongs to the pool.
-- - modification_ts: modification timestamp of the
--   option.
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS createOptionAuditDHCP4;
DELIMITER $$
CREATE PROCEDURE createOptionAuditDHCP4(IN modification_type VARCHAR(32),
                                        IN scope_id TINYINT(3) UNSIGNED,
                                        IN option_id BIGINT(20) UNSIGNED,
                                        IN subnet_id INT(10) UNSIGNED,
                                        IN host_id INT(10) UNSIGNED,
                                        IN network_name VARCHAR(128),
                                        IN pool_id BIGINT(20),
                                        IN modification_ts TIMESTAMP)
BEGIN
    # These variables will hold shared network id and subnet id that
    # we will select.
    DECLARE snid VARCHAR(128);
    DECLARE sid INT(10) UNSIGNED;

    # Cascade transaction flag is set to 1 to prevent creation of
    # the audit entries for the options when the options are
    # created as part of the parent object creation or update.
    # For example: when the option is added as part of the subnet
    # addition, the cascade transaction flag is equal to 1. If
    # the option is added into the existing subnet the cascade
    # transaction is equal to 0. Note that depending on the option
    # scope the audit entry will contain the object_type value
    # of the parent object to cause the server to replace the
    # entire subnet. The only case when the object_type will be
    # set to 'dhcp4_options' is when a global option is added.
    # Global options do not have the owner.
    IF @cascade_transaction IS NULL OR @cascade_transaction = 0 THEN
        # todo: host manager hasn't been updated to use audit
        # mechanisms so ignore host specific options for now.
        IF scope_id = 0 THEN
            # If a global option is added or modified, create audit
            # entry for the 'dhcp4_options' table.
            CALL createAuditEntryDHCP4('dhcp4_options', option_id, modification_type);
        ELSEIF scope_id = 1 THEN
            # If subnet specific option is added or modified, update
            # the modification timestamp of this subnet to allow the
            # servers to refresh the subnet information. This will
            # also result in creating an audit entry for this subnet.
            UPDATE dhcp4_subnet AS s SET s.modification_ts = modification_ts
                WHERE s.subnet_id = subnet_id;
        ELSEIF scope_id = 4 THEN
            # If shared network specific option is added or modified,
            # update the modification timestamp of this shared network
            # to allow the servers to refresh the shared network
            # information. This will also result in creating an
            # audit entry for this shared network.
           SELECT id INTO snid FROM dhcp4_shared_network WHERE name = network_name LIMIT 1;
           UPDATE dhcp4_shared_network AS n SET n.modification_ts = modification_ts
                WHERE n.id = snid;
        ELSEIF scope_id = 5 THEN
            # If pool specific option is added or modified, update
            # the modification timestamp of the owning subnet.
            SELECT dhcp4_pool.subnet_id INTO sid FROM dhcp4_pool WHERE id = pool_id;
            UPDATE dhcp4_subnet AS s SET s.modification_ts = modification_ts
                WHERE s.subnet_id = sid;
        END IF;
    END IF;
END $$
DELIMITER ;

# Recreate dhcp4_options_AINS trigger to pass timestamp to the updated
# version of the createOptionAuditDHCP4.
DROP TRIGGER IF EXISTS dhcp4_options_AINS;

# This trigger is executed after inserting a DHCPv4 option into the
# database. It creates appropriate audit entry for this option or
# a parent object owning this option.
DELIMITER $$
CREATE TRIGGER dhcp4_options_AINS AFTER INSERT ON dhcp4_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP4("create", NEW.scope_id, NEW.option_id, NEW.dhcp4_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id,
                                    NEW.modification_ts);
    END $$
DELIMITER ;

# Recreate dhcp4_options_AUPD trigger to pass timestamp to the updated
# version of the createOptionAuditDHCP4.
DROP TRIGGER IF EXISTS dhcp4_options_AUPD;

# This trigger is executed after updating a DHCPv4 option in the
# database. It creates appropriate audit entry for this option or
# a parent object owning this option.
DELIMITER $$
CREATE TRIGGER dhcp4_options_AUPD AFTER UPDATE ON dhcp4_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP4("update", NEW.scope_id, NEW.option_id, NEW.dhcp4_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id,
                                    NEW.modification_ts);
    END $$
DELIMITER ;

# Recreate dhcp4_options_ADEL trigger to pass timestamp to the updated
# version of the createOptionAuditDHCP4.
DROP TRIGGER IF EXISTS dhcp4_options_ADEL;

# This trigger is executed after deleting a DHCPv4 option in the
# database. It creates appropriate audit entry for this option or
# a parent object owning this option.
DELIMITER $$
CREATE TRIGGER dhcp4_options_ADEL AFTER DELETE ON dhcp4_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP4("delete", OLD.scope_id, OLD.option_id, OLD.dhcp4_subnet_id,
                                    OLD.host_id, OLD.shared_network_name, OLD.pool_id,
                                    NOW());
    END $$
DELIMITER ;


-- -----------------------------------------------------
--
-- New version of the createOptionAuditDHCP4 stored
-- procedure which updates modification timestamp of
-- a parent object when an option is modified.
--
-- The following parameters are passed to the procedure:
-- - modification_type: "create", "update" or "delete"
-- - scope_id: identifier of the option scope, e.g.
--   global, subnet specific etc. See dhcp_option_scope
--   for specific values.
-- - option_id: identifier of the option.
-- - subnet_id: identifier of the subnet if the option
--   belongs to the subnet.
-- - host_id: identifier of the host if the option
-- - belongs to the host.
-- - network_name: shared network name if the option
--   belongs to the shared network.
-- - pool_id: identifier of the pool if the option
--   belongs to the pool.
-- - pd_pool_id: identifier of the pool if the option
--   belongs to the pd pool.
-- - modification_ts: modification timestamp of the
--   option.
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS createOptionAuditDHCP6;
DELIMITER $$
CREATE PROCEDURE createOptionAuditDHCP6(IN modification_type VARCHAR(32),
                                        IN scope_id TINYINT(3) UNSIGNED,
                                        IN option_id BIGINT(20) UNSIGNED,
                                        IN subnet_id INT(10) UNSIGNED,
                                        IN host_id INT(10) UNSIGNED,
                                        IN network_name VARCHAR(128),
                                        IN pool_id BIGINT(20),
                                        IN pd_pool_id BIGINT(20),
                                        IN modification_ts TIMESTAMP)
BEGIN
    # These variables will hold shared network id and subnet id that
    # we will select.
    DECLARE snid VARCHAR(128);
    DECLARE sid INT(10) UNSIGNED;

    # Cascade transaction flag is set to 1 to prevent creation of
    # the audit entries for the options when the options are
    # created as part of the parent object creation or update.
    # For example: when the option is added as part of the subnet
    # addition, the cascade transaction flag is equal to 1. If
    # the option is added into the existing subnet the cascade
    # transaction is equal to 0. Note that depending on the option
    # scope the audit entry will contain the object_type value
    # of the parent object to cause the server to replace the
    # entire subnet. The only case when the object_type will be
    # set to 'dhcp6_options' is when a global option is added.
    # Global options do not have the owner.
    IF @cascade_transaction IS NULL OR @cascade_transaction = 0 THEN
        # todo: host manager hasn't been updated to use audit
        # mechanisms so ignore host specific options for now.
        IF scope_id = 0 THEN
            # If a global option is added or modified, create audit
            # entry for the 'dhcp6_options' table.
            CALL createAuditEntryDHCP6('dhcp6_options', option_id, modification_type);
        ELSEIF scope_id = 1 THEN
            # If subnet specific option is added or modified, update
            # the modification timestamp of this subnet to allow the
            # servers to refresh the subnet information. This will
            # also result in creating an audit entry for this subnet.
            UPDATE dhcp6_subnet AS s SET s.modification_ts = modification_ts
                WHERE s.subnet_id = subnet_id;
        ELSEIF scope_id = 4 THEN
            # If shared network specific option is added or modified,
            # update the modification timestamp of this shared network
            # to allow the servers to refresh the shared network
            # information. This will also result in creating an
            # audit entry for this shared network.
           SELECT id INTO snid FROM dhcp6_shared_network WHERE name = network_name LIMIT 1;
           UPDATE dhcp6_shared_network AS n SET n.modification_ts = modification_ts
               WHERE n.id = snid;
        ELSEIF scope_id = 5 THEN
            # If pool specific option is added or modified, update
            # the modification timestamp of the owning subnet.
            SELECT dhcp6_pool.subnet_id INTO sid FROM dhcp6_pool WHERE id = pool_id;
            UPDATE dhcp6_subnet AS s SET s.modification_ts = modification_ts
                WHERE s.subnet_id = sid;
        ELSEIF scope_id = 6 THEN
            # If pd pool specific option is added or modified, create
            # audit entry for the subnet which this pool belongs to.
            SELECT dhcp6_pd_pool.subnet_id INTO sid FROM dhcp6_pd_pool WHERE id = pd_pool_id;
            UPDATE dhcp6_subnet AS s SET s.modification_ts = modification_ts
                WHERE s.subnet_id = sid;
        END IF;
    END IF;
END $$
DELIMITER ;

# Recreate dhcp6_options_AINS trigger to pass timestamp to the updated
# version of the createOptionAuditDHCP6.
DROP TRIGGER IF EXISTS dhcp6_options_AINS;

# This trigger is executed after inserting a DHCPv6 option into the
# database. It creates appropriate audit entry for this option or
# a parent object owning this option.
DELIMITER $$
CREATE TRIGGER dhcp6_options_AINS AFTER INSERT ON dhcp6_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP6("create", NEW.scope_id, NEW.option_id, NEW.dhcp6_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id,
                                    NEW.pd_pool_id, NEW.modification_ts);
    END $$
DELIMITER ;

# Recreate dhcp6_options_AUPD trigger to pass timestamp to the updated
# version of the createOptionAuditDHCP6.
DROP TRIGGER IF EXISTS dhcp6_options_AUPD;

# This trigger is executed after updating a DHCPv6 option in the
# database. It creates appropriate audit entry for this option or
# a parent object owning this option.
DELIMITER $$
CREATE TRIGGER dhcp6_options_AUPD AFTER UPDATE ON dhcp6_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP6("update", NEW.scope_id, NEW.option_id, NEW.dhcp6_subnet_id,
                                    NEW.host_id, NEW.shared_network_name, NEW.pool_id,
                                    NEW.pd_pool_id, NEW.modification_ts);
    END $$
DELIMITER ;

# Recreate dhcp6_options_ADEL trigger to pass timestamp to the updated
# version of the createOptionAuditDHCP6.
DROP TRIGGER IF EXISTS dhcp6_options_ADEL;

# This trigger is executed after deleting a DHCPv6 option in the
# database. It creates appropriate audit entry for this option or
# a parent object owning this option.
DELIMITER $$
CREATE TRIGGER dhcp6_options_ADEL AFTER DELETE ON dhcp6_options
    FOR EACH ROW
    BEGIN
        CALL createOptionAuditDHCP6("delete", OLD.scope_id, OLD.option_id, OLD.dhcp6_subnet_id,
                                    OLD.host_id, OLD.shared_network_name, OLD.pool_id,
                                    OLD.pd_pool_id, NOW());
    END $$
DELIMITER ;

# Update the schema version number
UPDATE schema_version
SET version = '8', minor = '2';

# This line concludes database upgrade to version 8.2.

# Create hostname index for host reservations
CREATE INDEX hosts_by_hostname ON hosts (hostname);

# Create hostname index for lease4
CREATE INDEX lease4_by_hostname ON lease4 (hostname);

# Create hostname index for lease6
CREATE INDEX lease6_by_hostname ON lease6 (hostname);

# Update the schema version number
UPDATE schema_version
SET version = '9', minor = '0';

# This line concludes database upgrade to version 9.0.

# Add new DDNS related columns to shared networks and subnets
ALTER TABLE dhcp4_shared_network
    ADD COLUMN ddns_send_updates TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_no_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_client_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_replace_client_name TINYINT(3) DEFAULT NULL,
    ADD COLUMN ddns_generated_prefix VARCHAR(255) DEFAULT NULL,
    ADD COLUMN ddns_qualifying_suffix VARCHAR(255) DEFAULT NULL;

ALTER TABLE dhcp6_shared_network
    ADD COLUMN ddns_send_updates TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_no_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_client_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_replace_client_name TINYINT(3) DEFAULT NULL,
    ADD COLUMN ddns_generated_prefix VARCHAR(255) DEFAULT NULL,
    ADD COLUMN ddns_qualifying_suffix VARCHAR(255) DEFAULT NULL;

ALTER TABLE dhcp4_subnet
    ADD COLUMN ddns_send_updates TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_no_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_client_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_replace_client_name TINYINT(3) DEFAULT NULL,
    ADD COLUMN ddns_generated_prefix VARCHAR(255) DEFAULT NULL,
    ADD COLUMN ddns_qualifying_suffix VARCHAR(255) DEFAULT NULL;

ALTER TABLE dhcp6_subnet
    ADD COLUMN ddns_send_updates TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_no_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_override_client_update TINYINT(1) DEFAULT NULL,
    ADD COLUMN ddns_replace_client_name TINYINT(3) DEFAULT NULL,
    ADD COLUMN ddns_generated_prefix VARCHAR(255) DEFAULT NULL,
    ADD COLUMN ddns_qualifying_suffix VARCHAR(255) DEFAULT NULL;

# Update the schema version number
UPDATE schema_version
SET version = '9', minor = '1';

# This line concludes database upgrade to version 9.1.


# Notes:
#
# Indexes
# =======
# It is likely that additional indexes will be needed.  However, the
# increase in lookup performance from these will come at the expense
# of a decrease in performance during insert operations due to the need
# to update the indexes.  For this reason, the need for additional indexes
# will be determined by experiment during performance tests.
#
# The most likely additional indexes will cover the following columns:
#
# hwaddr and client_id
# For lease stability: if a client requests a new lease, try to find an
# existing or recently expired lease for it so that it can keep using the
# same IP address.
#
# Field Sizes
# ===========
# If any of the VARxxx field sizes are altered, the lengths in the MySQL
# backend source file (mysql_lease_mgr.cc) must be correspondingly changed.
#
# Portability
# ===========
# The 'ENGINE = INNODB' on some tables is not portable to another database
# and will need to be removed.
#
# Some columns contain binary data so are stored as VARBINARY instead of
# VARCHAR.  This may be non-portable between databases: in this case, the
# definition should be changed to VARCHAR.