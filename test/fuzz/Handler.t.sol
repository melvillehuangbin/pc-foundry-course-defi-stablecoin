// SPDX-License-Identifier

pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";


contract Handler is Test {

    DSCEngine dscengine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    address[] private collateralTokens;
    uint96 private constant MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    MockV3Aggregator ethUsdPriceFeed;

    constructor(DSCEngine _dscengine, DecentralizedStableCoin _dsc) {
        dscengine = _dscengine;
        dsc = _dsc;

        collateralTokens = dscengine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscengine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amountDscToMint, uint256 addressCollateralSeed) public {

        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressCollateralSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscengine.getAccountInformation(sender);
        console.log("Collateral value in USD: ", collateralValueInUsd);
        console.log("Total DSC Minted: ", totalDscMinted);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        uint256 maxDscToMintLog = uint256(maxDscToMint);
        console.log("Max DSC To Mint: ", maxDscToMintLog);
        amountDscToMint = bound(amountDscToMint, 0, uint256(maxDscToMint));
        if (amountDscToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        dscengine.mintDsc(amountDscToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscengine), amountCollateral);
        dscengine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // might push the same user twice
        usersWithCollateralDeposited.push(msg.sender);
    }
    
    function redeemCollateral(uint256 collateralSeed, uint256 amountToRedeem) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // uint256 maxCollateralToRedeem = dscengine.getCollateralDeposited(msg.sender, address(collateral));
        amountToRedeem = bound(amountToRedeem, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountToRedeem);
        collateral.approve(address(dscengine), amountToRedeem);
        dscengine.depositCollateral(address(collateral), amountToRedeem);
        dscengine.redeemCollateral(address(collateral), amountToRedeem);
        vm.stopPrank();
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPrice = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPrice);
    // }
    
    // Helpers
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock) {
        if (collateralSeed % 2 == 0 ) {
            return weth;
        } else {
            return wbtc;
        }
    }
}