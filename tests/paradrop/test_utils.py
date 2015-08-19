import copy
import os

from .mock import MockChute, MockChuteStorage, writeTempFile


NETWORK_WAN_CONFIG = """
config interface wan #__PARADROP__
    option ifname 'eth0'
    option proto 'dhcp'
"""


def test_addresses():
    """
    Test IP address utility functions
    """
    from paradrop.lib.utils import addresses

    ipaddr = "192.168.1.1"
    assert addresses.isIpValid(ipaddr)

    ipaddr = "192.168.1.256"
    assert not addresses.isIpValid(ipaddr)

    chute = MockChute(name="first")
    chute.IPs.append("192.168.1.1")
    chute.SSIDs.append("Paradrop")
    chute.staticIPs.append("192.168.33.1")
    storage = MockChuteStorage()
    storage.chuteList.append(chute)

    assert not addresses.isIpAvailable("192.168.1.1", storage, "second")
    assert addresses.isIpAvailable("192.168.2.1", storage, "second")
    assert addresses.isIpAvailable("192.168.1.1", storage, "first")
    
    assert not addresses.isWifiSSIDAvailable("Paradrop", storage, "second")
    assert addresses.isWifiSSIDAvailable("available", storage, "second")
    assert addresses.isWifiSSIDAvailable("Paradrop", storage, "first")

    assert not addresses.isStaticIpAvailable("192.168.33.1", storage, "second")
    assert addresses.isStaticIpAvailable("192.168.35.1", storage, "second")
    assert addresses.isStaticIpAvailable("192.168.33.1", storage, "first")

    assert not addresses.checkPhyExists(-100)

    ipaddr = "192.168.1.1"
    netmask = "255.255.255.0"

    assert addresses.incIpaddr("192.168.1.1") == "192.168.1.2"
    assert addresses.incIpaddr("fail") is None

    assert addresses.maxIpaddr(ipaddr, netmask) == "192.168.1.254"
    assert addresses.maxIpaddr(ipaddr, "fail") is None

    assert addresses.getSubnet(ipaddr, netmask) == "192.168.1.0"
    assert addresses.getSubnet(ipaddr, "fail") is None

    # Test with nothing in the cache
    assert addresses.getInternalIntfList(chute) is None
    assert addresses.getGatewayIntf(chute) == (None, None)
    assert addresses.getWANIntf(chute) is None

    # Now put an interface in the cache
    ifaces = [{
        'internalIntf': "eth0",
        'netType': "wan",
        'externalIpaddr': "192.168.1.1"
    }]
    chute.setCache("networkInterfaces", ifaces)

    assert addresses.getInternalIntfList(chute) == ["eth0"]
    assert addresses.getGatewayIntf(chute) == ("192.168.1.1", "eth0")
    assert addresses.getWANIntf(chute) == ifaces[0]

def test_uci():
    """
    Test UCI file utility module
    """
    from paradrop.lib.utils import uci
    from paradrop.lib import settings

    # Test functions for finding path to UCI files
    settings.UCI_CONFIG_DIR = "/tmp/config"
    assert uci.getSystemConfigDir() == "/tmp/config"
    assert uci.getSystemPath("network") == "/tmp/config/network"

    # Test stringify function
    assert uci.stringify("a") == "a"
    blob = {"a": "b"}
    assert uci.stringify(blob) == blob
    blob = {"a": {"b": "c"}}
    assert uci.stringify(blob) == blob
    blob = {"a": ["b", "c"]}
    assert uci.stringify(blob) == blob
    blob = {"a": 5}
    strblob = {"a": "5"}
    assert uci.stringify(blob) == strblob
    assert uci.isMatch(blob, strblob)

    # Write a realistic configuration and load with uci module
    path = writeTempFile(NETWORK_WAN_CONFIG)
    config = uci.UCIConfig(path)

    # Test if it found the config section that we know should be there
    empty = {}
    assert config.getConfig(empty) == []
    match = {"type": "interface", "name": "wan", "comment": "__PARADROP__"}
    assert len(config.getConfig(match)) == 1
    match = {"type": "interface", "name": "wan", "comment": "chute"}
    assert config.getConfig(match) == []
    assert config.getConfigIgnoreComments(empty) == []
    assert len(config.getConfigIgnoreComments(match)) == 1

    # More existence tests
    assert not config.existsConfig(empty, empty)
    match_config = {
        "type": "interface",
        "name": "wan",
        "comment": "__PARADROP__"
    }
    match_options = {
        "ifname": "eth0",
        "proto": "dhcp"
    }
    assert config.existsConfig(match_config, match_options)

    # Test adding and removing
    config.delConfigs([(match_config, match_options)])
    assert not config.existsConfig(match_config, match_options)
    config.addConfigs([(match_config, match_options)])
    assert config.existsConfig(match_config, match_options)
    config.delConfig(match_config, match_options)
    assert not config.existsConfig(match_config, match_options)
    config.addConfig(match_config, match_options)
    assert config.existsConfig(match_config, match_options)

    # Get configuration by chute name
    assert config.getChuteConfigs("none") == []
    assert len(config.getChuteConfigs("__PARADROP__")) == 1

    # Test saving and reloading
    config.save(backupToken="backup")
    config2 = uci.UCIConfig(path)

    # Simple test for the equality operators
    assert config == config2
    assert not (config != config2)

    # Test chuteConfigsMatch function
    assert not uci.chuteConfigsMatch(config.getChuteConfigs("__PARADROP__"),
            config2.getChuteConfigs("none"))
    assert uci.chuteConfigsMatch(config.getChuteConfigs("__PARADROP__"),
            config2.getChuteConfigs("__PARADROP__"))
