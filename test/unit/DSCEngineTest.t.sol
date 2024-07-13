// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {MockTransferFailedDSC} from "../../test/mocks/MockTransferFailedDSC.sol";
import {MockMintFailedDSC} from "../../test/mocks/MockMintFailedDSC.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscengine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant amountToMint = 100 ether;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscengine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////////////////
    // Constructor Tests    //////////////////
    //////////////////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, weth);
    }

    //////////////////////////////////////////
    // depositCollateralAndMintDsc Tests    //
    //////////////////////////////////////////

    function testRevertIfHealthFactorIsBroken() public {

        // Arrange
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);

        // Assert/Act
        uint256 expectedHealthFactor =
            dscengine._calculateHealthFactor(amountToMint, dscengine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscengine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
    }

    modifier depositAndMintCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);
        dscengine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();
        _;
    }

    //////////////////////////////////////////
    // depositCollateral Tests              //
    //////////////////////////////////////////


    function testRevertsIfCollateralZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(USER, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscengine.depositCollateral(weth, 0);
    }

    function testRandomTokenNotInEngineCannotBeDeposited() public {
        ERC20Mock randToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            STARTING_ERC20_BALANCE
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscengine.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
    }

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    function testCollateralDepositedEventEmitted() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);

        vm.expectEmit(address(dscengine));
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscengine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralCanBeDeposited() public depositCollateral {
        uint256 userCollateralDeposited = dscengine.getCollateralDeposited(USER, weth);
        assertEq(userCollateralDeposited, AMOUNT_COLLATERAL);
    }

    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockTransferFailedDSC mockDSC = new MockTransferFailedDSC();
        tokenAddresses = [address(mockDSC)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(mockDSCEngine));
        vm.stopPrank();

        // Arrange - User
        vm.startPrank(owner);
        ERC20Mock(address(mockDSC)).approve(address(mockDSCEngine), AMOUNT_COLLATERAL);

        // Act/ Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCEngine.depositCollateral(address(mockDSC), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralCanBeDepositedWithoutMinting() public depositCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testAccountInformationCanBeRetrievedAfterDeposited() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscengine.getAccountInformation(USER);
        uint256 tokenAmount = dscengine.getTokenAmountFromUsd(address(weth), collateralValueInUsd);
        assertEq(tokenAmount, AMOUNT_COLLATERAL);
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscengine
            .getAccountInformation(USER);
        uint256 expectedDepositAmount = dscengine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, 0);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);
        dscengine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }


    //////////////////////////////////////////
    // mintDSC Tests                        //
    //////////////////////////////////////////

    function testRevertIfAmountMintedLessThanZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(USER, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscengine.mintDsc(0);
    }

    function testRevertMintDscIfHealthFactorBroken() public depositCollateral {
        // Arrange
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (uint256(price) * ADDITIONAL_FEED_PRECISION * AMOUNT_COLLATERAL) / PRECISION;
        vm.startPrank(USER);
        
        // Act/Assert
        uint256 expectedHealthFactor = dscengine._calculateHealthFactor(amountToMint, dscengine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscengine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testRevertIfMintFailed() public { 
        // Assert - SetUp
        MockMintFailedDSC mockDSC = new MockMintFailedDSC();
        priceFeedAddresses = [ethUsdPriceFeed];
        tokenAddresses = [weth];
        address owner = msg.sender;
        
        vm.prank(owner);
        DSCEngine mockDSCEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(mockDSCEngine));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDSCEngine), AMOUNT_COLLATERAL);

        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDSCEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    //////////////////////////////////////////
    // Other Tests                        ////
    //////////////////////////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // expected = 15e18 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscengine.getUsdValue(weth, ethAmount);
        assert(actualUsd == expectedUsd);
    }


    function testGetHealthFactor() public depositAndMintCollateral {
        uint256 expectedHealthFactor = 5000e18;
        uint256 healthFactor = dscengine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, healthFactor);
    }

    //////////////////////////////////////////
    // redeemCollateralForDSC Tests    ///////
    //////////////////////////////////////////

    // function burnDSC
    // function redeemCollateral

    function testRevertIfBurnAmountIsZero() public depositAndMintCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscengine.burnDSC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dscengine.burnDSC(1);
        vm.stopPrank();
    }

    function testDscCanBeBurn() public depositAndMintCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dscengine), amountToMint);
        dscengine.burnDSC(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    //////////////////////////////////////////
    // redeemCollateral Tests    /////////////
    //////////////////////////////////////////


}
