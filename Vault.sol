pragma solidity >=0.5.0 <0.6.0;

import "./ds-proxy/src/proxy.sol";
import "./accounting/contracts/Accounting.sol";
import "./accounting/lib/math-lib.sol";

// Lockr v 1

contract LockrData is ProxyData, Accounting {
    uint ONE_PERCENT_WAD = 10 ** 16;// 1 wad is 10^18, so 1% in wad is 10^16
    uint ONE_WAD = 10 ** 18;
    uint public version = 1;
    struct Vault {
        uint64 deadline;
        uint64 created;
        uint feeWad;
        Account account;
    } 

    Vault[] internal vaults;

    event VaultCreated();
    event EarlyWithdrawal();
    event Withdrawal();
}

contract Lockr is LockrData {
    using DSMath for uint;

    modifier onlyActive(uint vault) {
        require(vaults.length > vault, "Vault doesn't exist");
        require(vaults[vault].deadline > block.timestamp, "Vault is inactive");
        _;
    }

    modifier onlyInactive(uint vault) {
        require(vaults.length > vault, "Vault doesn't exist");
        require(vaults[vault].deadline <= block.timestamp, "Vault is still active");
        _;
    }

    function init() external auth {
        require(version == 0, "Already Initialized");
        version = 1;
        ONE_PERCENT_WAD = 10 ** 16;// 1 wad is 10^18, so 1% in wad is 10^16
        ONE_WAD = 10 ** 18;
        base.name = "Base";
        vaults.length = 0;
    }

    function createVault(uint64 deadline, uint feeWad) external auth returns(uint index) {
        require(deadline > uint64(block.timestamp), "Invalid deadline");
        require(feeWad >= ONE_PERCENT_WAD * 10 && feeWad <= 50 * ONE_PERCENT_WAD, "Fee out of range");
        vaults.length++;
        index = vaults.length - 1;
        Vault storage v = vaults[index];
        v.created = uint64(block.number);
        v.deadline = deadline;
        v.feeWad = feeWad;
        v.account.name = bytes32(index);
        emit VaultCreated();
    }

    function depositETHToVault(uint vault) external  payable onlyActive(vault) {
        Vault storage v = vaults[vault];
        depositETH(v.account, msg.sender, msg.value);
    }

    function depositTokenToVault(uint vault, address token, uint value) external onlyActive(vault) {
        Vault storage v = vaults[vault];
        depositToken(v.account, msg.sender, token, value);
    }

    function withdrawETH(uint vault, uint value) external auth onlyInactive(vault) {
        Vault storage v = vaults[vault];
        sendETH(v.account, msg.sender, value);
        emit Withdrawal();
    }

    function withdrawETHEarly(uint vault, uint value) external auth onlyActive(vault) {
        Vault storage v = vaults[vault];
        require(v.account.balanceETH <= value, "Invalid amount");
        uint fee = value.wmul(v.feeWad);
        uint toSend = value.wmul(ONE_WAD.sub(v.feeWad));
        assert(fee.add(toSend) == value);

        // TODO: Fix contract to address payable for v.0.6: payable(address(x))
        sendETH(v.account, address(bytes20(address(proxyAuth))), fee);
        sendETH(v.account, msg.sender, toSend);
        emit EarlyWithdrawal();
    }

    function withdrawToken(uint vault, address token, uint value) external auth onlyInactive(vault) {
        Vault storage v = vaults[vault];
        sendToken(v.account, token, msg.sender, value);
        emit Withdrawal();
    }

    function withdrawTokenEarly(uint vault, address token, uint value) external auth onlyActive(vault) {
        Vault storage v = vaults[vault];
        require(v.account.tokenBalances[token] <= value, "Invalid amount");
        uint fee = value.wmul(v.feeWad);
        uint toSend = value.wmul(ONE_WAD.sub(v.feeWad));
        assert(fee.add(toSend) == value);

        // TODO: Fix contract to address payable for v.0.6: payable(address(x))
        sendToken(v.account, token, address(bytes20(address(proxyAuth))), fee);
        sendToken(v.account, token, msg.sender, toSend);
        emit EarlyWithdrawal();
    }

    function vaultsNr() external view returns(uint) {
        return vaults.length;
    }
}