// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscengine;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscengine, config) = deployer.run();
        (
            ,
            ,
            weth,
            wbtc,
            
        ) = config.activeNetworkConfig();
        targetContract(address(dscengine));
    }

    function invariant_testProtocolMustHaveMoreValueThanTotalSupply() public {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscengine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscengine));

        uint256 wethValue = dscengine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscengine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}

