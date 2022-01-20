pragma solidity > 0.6.6;

import './libraries/UniswapV2Library.sol';
import './libraries/TransferHelper.sol';
import './libraries/LowGasSafeMath.sol';
import './libraries/PoolAddress.sol';
import './libraries/TickMath.sol';
import "./libraries/SafeCast.sol";
import './interfaces/V2/IUniswapV2Router02.sol';
import './interfaces/V2/IUniswapV2Pair.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/V3/ISwapRouter.sol';
import './interfaces/V3/IUniswapV3Factory.sol';
import './interfaces/V3/IUniswapV3Pool.sol';
import 'hardhat/console.sol';


contract ArbitrageV3toV2 {
  using SafeCast for uint256;

  address public factoryV2;
  address public factoryV3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  uint constant deadline = 10 days;
  ISwapRouter public swapRouterV3;
  address public swapRouterV2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
  address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  enum Direction { V2ToV3, V3ToV2 }

  constructor(address _factoryV2, address _routerV3) public {
    factoryV2 = _factoryV2;
    swapRouterV3 = ISwapRouter(_routerV3);
  }


  struct SwapCallbackData {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address payer;
  }

  //For test purpose, method to swap WETH to ERC-20 token at V3
  function tokenSwapV3(
    address asset,//trade token: UNI
    uint amount //ETH amount
  ) external payable{
    console.log('Swap at V3');
    // pool address for asset withdrawal(borrow)
    //TODO flash pool should not be hardcoded
    address poolAddress = IUniswapV3Factory(factoryV3).getPool(WETH, asset, 3000);
    require(poolAddress != address(0), 'This pool does not exist');
    console.log('Withdrawal Pool Address');
    console.log(poolAddress);

    TransferHelper.safeApprove(WETH, address(swapRouterV3), amount);
    //fetch tokenIn asset from msg.sender
    require(IERC20(WETH).transferFrom(msg.sender, address(this), amount), 'transferFrom failed.');

    //swap token on V3 (buy UNI here)
    ISwapRouter.ExactInputSingleParams memory params =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: WETH,
        tokenOut: asset,
        fee: 3000,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: amount,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });

    uint256 amountOut = swapRouterV3.exactInputSingle(params);

    console.log('amountOut');
    console.log(amountOut);
    //return left amount to msg.sender
    //ERC20(asset).balanceOf(address(this)) should be the same amount as amountOut, but just in case send everything
    TransferHelper.safeTransfer(asset, msg.sender, IERC20(asset).balanceOf(address(this)));


  }
  
  //Flashswap swap arbitrage method. withdraw specified WETH from V3, then swap it to ERC20 asset at V2,
  //thereafter return ERC20 asset to V3. if amount left, transfer it to msg.sender.
  function arbitrageV3ToV2(
    address asset,//trade token: UNI
    uint amount //ETH amount
  ) external payable{
    console.log('startArbitrageV3toV2');
    // pool address for asset withdrawal(borrow)
    //TODO the fee is hardcoded, but this should be be abole to parameterize
    address poolAddress = IUniswapV3Factory(factoryV3).getPool(WETH, asset, 3000);
    require(poolAddress != address(0), 'This pool does not exist');
    console.log('Withdrawal Pool Address');
    console.log(poolAddress);


    //swap token on V3 (buy UNI here)
    ISwapRouter.ExactOutputSingleParams memory params =
      ISwapRouter.ExactOutputSingleParams({
      tokenIn: asset,
      tokenOut: WETH,
      fee: 3000,
      recipient: address(this),
      deadline: block.timestamp,
      amountOut: amount,
      amountInMaximum: 2**256 - 1,//MAX INT
      sqrtPriceLimitX96: 0
      });

    uint256 amountIn = exactOutputInternal(
      params.amountOut,
      params.recipient,
      params.sqrtPriceLimitX96,
      SwapCallbackData({tokenIn: params.tokenIn, tokenOut: params.tokenOut, fee: params.fee, payer: msg.sender})
    );

    console.log('amountIn(UNI) we should have paid in callback process');
    console.log(amountIn);

    console.log('receive WETH');
    console.log(IERC20(WETH).balanceOf(address(this)));
    TransferHelper.safeTransfer(WETH, msg.sender, IERC20(WETH).balanceOf(address(this)));




  }


  function exactOutputInternal(
    uint256 amountOut,
    address recipient,
    uint160 sqrtPriceLimitX96,
    SwapCallbackData memory data
  ) private returns (uint256 amountIn) {
    // allow swapping to the router address with address 0
    if (recipient == address(0)) recipient = address(this);
    address tokenOut = data.tokenOut;
    address tokenIn = data.tokenIn;
    uint24 fee = data.fee;

    bool zeroForOne = tokenIn < tokenOut;
    console.log('zeroForOne');
    console.log(zeroForOne);

    console.log(getPool(tokenIn, tokenOut, fee).token0());
    console.log(getPool(tokenIn, tokenOut, fee).token1());

    (int256 amount0Delta, int256 amount1Delta) =
    getPool(tokenIn, tokenOut, fee).swap(
      recipient,
      zeroForOne,
      -amountOut.toInt256(),
      sqrtPriceLimitX96 == 0
      ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
      : sqrtPriceLimitX96,
      abi.encode(data)
    );

    uint256 amountOutReceived;
    (amountIn, amountOutReceived) = zeroForOne
    ? (uint256(amount0Delta), uint256(-amount1Delta))
    : (uint256(amount1Delta), uint256(-amount0Delta));
    // it's technically possible to not receive the full output amount,
    // so if no price limit has been specified, require this possibility away
    if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
  }

  /// @dev Returns the pool for the given token pair and fee. The pool contract may or may not exist.
  function getPool(
    address tokenA,
    address tokenB,
    uint24 fee
  ) private view returns (IUniswapV3Pool) {
    return IUniswapV3Pool(PoolAddress.computeAddress(factoryV3, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
  }

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata _data
  ) external {
    console.log('uniswapV3SwapCallback');
    SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));

    console.log('amount0Delta');
    console.logInt(amount0Delta);
    console.log('amount1Delta');
    console.logInt(amount1Delta);
    console.log('TokenIn');
    console.log(data.tokenIn);
    console.log('TokenOut');
    console.log(data.tokenOut);
    console.log('Payer');
    console.log(data.payer);

    uint256 amountIn;
    uint256 amountOutReceived;
    bool zeroForOne = data.tokenIn < data.tokenOut;

    (amountIn, amountOutReceived) = zeroForOne
    ? (uint256(amount0Delta), uint256(-amount1Delta))
    : (uint256(amount1Delta), uint256(-amount0Delta));

    console.log('amountIn');
    console.logInt(amountIn);
    console.log('amountOutReceived');
    console.logInt(amountOutReceived);

    //Swap received token(tokenOut) to returned token(TokenIn).
    uint256 swappedAmount = swapTokensAtV2(data.tokenOut, data.tokenIn, amountOutReceived);
    console.log('swapped Amount at V2');
    console.log(swappedAmount);
    if(swappedAmount < amountIn){
      TransferHelper.safeTransfer(data.tokenIn, msg.sender, swappedAmount);
      TransferHelper.safeTransferFrom(data.tokenIn, data.payer, msg.sender, amountIn-swappedAmount);
    } else {
      TransferHelper.safeTransfer(data.tokenIn, msg.sender, amountIn);
      if(swappedAmount > amountIn){
        TransferHelper.safeTransfer(data.tokenIn, data.payer, swappedAmount - amountIn);
      }
    }

  }



  //normal swap method at V2
  function swapTokensAtV2(address tokenIn, address tokenOut, uint256 amountIn)
  internal
  returns (uint256 amountOut){
    address[] memory path;

    if (tokenIn == WETH || tokenOut == WETH) {
      path = new address[](2);
      path[0] = tokenIn;
      path[1] = tokenOut;
    } else {
      path = new address[](3);
      path[0] = tokenIn;
      path[1] = WETH;
      path[2] = tokenOut;
    }

    //[amountIn, amountOut]
    uint[] memory amounts = UniswapV2Library.getAmountsOut(factoryV2, amountIn, path);
    uint amountOutMin = amounts[1];

    require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, 'withdrawn token is less than claimed amount');

    //then we will call swapExactTokensForTokens
    //for the deadline we will pass in block.timestamp
    //the deadline is the latest time the trade is valid for
    TransferHelper.safeApprove(tokenIn, address(swapRouterV2), amountIn);
    uint[] memory v2swappedAmount = IUniswapV2Router02(swapRouterV2).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp+10000);
    console.log(v2swappedAmount.length);
    for (uint i=0; i<v2swappedAmount.length; i++) {
      console.log(v2swappedAmount[i]);
    }
    return v2swappedAmount[v2swappedAmount.length-1];

  }



}
