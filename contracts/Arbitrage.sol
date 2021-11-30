pragma solidity > 0.6.6;

import './libraries/UniswapV2Library.sol';
import './libraries/TransferHelper.sol';
import './libraries/LowGasSafeMath.sol';
import './interfaces/V2/IUniswapV2Router02.sol';
import './interfaces/V2/IUniswapV2Pair.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/V3/ISwapRouter.sol';
import './interfaces/V3/IUniswapV3Factory.sol';
import './interfaces/V3/IUniswapV3Pool.sol';
import 'hardhat/console.sol';

contract Arbitrage {
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

  function arbitrageV2ToV3(
    address input,
    address output,
    uint amountIn, //amountIn may not be needed. usually 0
    uint amountOut
  ) external {
    console.log('startArbitrage');
    address pairAddress = IUniswapV2Factory(factoryV2).getPair(input, output);
    require(pairAddress != address(0), 'This pool does not exist');
    console.log('Pair Address');
    console.log(pairAddress);

    address token0 = IUniswapV2Pair(pairAddress).token0();

    (uint amount0, uint amount1) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
    //Specify only output amount and make inputAmount 0. input token will be returned in uniswapV2Call
    IUniswapV2Pair(pairAddress).swap(amount0, amount1, address(this), bytes('not empty'));

  }


  struct FlashCallbackData {
    address tokenIn;
    address tokenOut;
    uint256 amount;
    address payer;
  }

  function arbitrageV3ToV2(
    address input,//token to be withdrawn from pool
    address output,//token to be swapped to
    uint amount //token amount to be withdrawn from pool
  ) external payable{
    console.log('startArbitrageV3toV2');
    // pool address for asset withdrawal(borrow)
    //TODO flash pool should not be hardcoded
    address poolAddress = IUniswapV3Factory(factoryV3).getPool(USDC, input, 500);
    require(poolAddress != address(0), 'This pool does not exist');
    console.log('Withdrawal Pool Address');
    console.log(poolAddress);

    address token0 = IUniswapV3Pool(poolAddress).token0();
    (uint amount0, uint amount1) = input == token0 ? (amount, uint(0)) : (uint(0), amount);

    IUniswapV3Pool(poolAddress).flash(
        address(this),
        amount0,
        amount1,
        abi.encode(
          FlashCallbackData({
            tokenIn: input,
            tokenOut: output,
            amount: amount,
            payer: msg.sender
          })
        )
      );

  }

  function uniswapV2Call(
    address _sender,
    uint _amount0,
    uint _amount1,
    bytes calldata _data
  ) external {

    console.log('uniswapV2Call');

    address[] memory path = new address[](2);
    address[] memory oldpath = new address[](2);
    //amountToken is amount of token acquired from V2 Pair pool
    uint amountToken = _amount0 == 0 ? _amount1 : _amount0;



    address token0 = IUniswapV2Pair(msg.sender).token0();
    address token1 = IUniswapV2Pair(msg.sender).token1();


    require(
      msg.sender == UniswapV2Library.pairFor(factoryV2, token0, token1),
      'Unauthorized'
    );
    require(_amount0 == 0 || _amount1 == 0);

    //path represents the direction of V3 swap
    path[0] = _amount0 == 0 ? token1 : token0;
    path[1] = _amount0 == 0 ? token0 : token1;

    //token is the token acquired from V2 pair pool
    IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);
    //otherToken is the token witch will be returned to V2 after V3 swapping
    IERC20 otherToken = IERC20(_amount0 == 0 ? token0 : token1);

    console.log('Initial otherToken balance');
    console.log(otherToken.balanceOf(address(this)));

    token.approve(address(swapRouterV3), amountToken);

    //oldpath represents the direction of previous V2 swap
    oldpath[0] = _amount0 == 0 ? token0 : token1;
    oldpath[1] = _amount0 == 0 ? token1 : token0;

    //required token amount to be repaid to V2
    uint amountRequired = UniswapV2Library.getAmountsIn(
      factoryV2,
      amountToken,
      oldpath
    )[0];

    //swap token on V3
    ISwapRouter.ExactInputSingleParams memory params =
    ISwapRouter.ExactInputSingleParams({
    tokenIn: path[0],
    tokenOut: path[1],
    fee: 3000,
    recipient: address(this),
    deadline: block.timestamp,
    amountIn: amountToken,
    amountOutMinimum: 0,
    sqrtPriceLimitX96: 0
    });

    uint amountReceived = swapRouterV3.exactInputSingle(params);

    console.log('amountRequired');
    console.log(amountRequired);
    console.log('amountReceived');
    console.log(amountReceived);

    //    require(
    //      amountReceived >= amountRequired,
    //      'arbitrage failed'
    //    );

    otherToken.transfer(msg.sender, amountRequired);
    console.log(otherToken.balanceOf(address(this)));
    //otherToken.transfer(tx.origin, amountReceived - amountRequired);
  }


  function uniswapV3FlashCallback(
    uint256 fee0,
    uint256 fee1,
    bytes calldata data
  ) external {
    FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
    decoded = abi.decode(data, (FlashCallbackData));

//    CallbackValidation.verifyCallback(factory, decoded.poolKey);

    address poolAddress = IUniswapV3Factory(factoryV3).getPool(decoded.tokenIn, decoded.tokenOut, 3000);
    require(poolAddress != address(0), 'This pool does not exist');
    console.log('V3 Swap Pool Address');
    console.log(poolAddress);
    console.log('WETH');
    console.log(IERC20(decoded.tokenIn).balanceOf(address(this)));
    console.log('BAT');
    console.log(IERC20(decoded.tokenOut).balanceOf(address(this)));

    require(
      msg.sender == IUniswapV3Factory(factoryV3).getPool(IUniswapV3Pool(msg.sender).token0(), IUniswapV3Pool(msg.sender).token1(), IUniswapV3Pool(msg.sender).fee()),
      'Unauthorized'
    );
    require(fee0 == 0 || fee1 == 0, 'withdraw only one token');
    require(IERC20(decoded.tokenIn).balanceOf(address(this)) >= decoded.amount, 'withdrawn token do not have sufficient balance');

    //swap withdraw token to another one at V2 protocol
    uint256 TokenOutV2Amount = swapTokensAtV2(decoded.tokenIn, decoded.tokenOut, decoded.amount);
    console.log(TokenOutV2Amount);

    console.log('WETH');
    console.log(IERC20(decoded.tokenIn).balanceOf(address(this)));
    console.log('BAT');
    console.log(IERC20(decoded.tokenOut).balanceOf(address(this)));

    //swap whole swapped token to original one at V3 protocol
    TransferHelper.safeApprove(decoded.tokenOut, address(swapRouterV3), TokenOutV2Amount);
    uint BAT_balance = IERC20(decoded.tokenOut).balanceOf(address(this));

    // profitable check
    // exactInputSingle will fail if this amount not met

    //this is the returned amount of tokenIn to original withdrawn pool
    uint256 amountOwned = fee0 == 0 ? LowGasSafeMath.add(decoded.amount, fee1) : LowGasSafeMath.add(decoded.amount, fee0);
    console.log('swapped amount at V2');
    console.log(amountOwned);

    // call exactInputSingle for swapping token1 for token0 in pool w/fee2
    uint256 amountOutV3 =
    swapRouterV3.exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
          tokenIn: decoded.tokenOut,
          tokenOut: decoded.tokenIn,
          fee: 3000,
          recipient: address(this),
          deadline: block.timestamp + 200,
          amountIn: TokenOutV2Amount,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
        })
    );

    console.log('Complete swap at V3');
    console.log('WETH');
    console.log(IERC20(decoded.tokenIn).balanceOf(address(this)));
    console.log('BAT');
    console.log(IERC20(decoded.tokenOut).balanceOf(address(this)));

    //return borrowed currency to V3 Pool
    TransferHelper.safeApprove(decoded.tokenIn, address(this), amountOwned);
    if (amountOwned > 0) {
      TransferHelper.safeTransfer(decoded.tokenIn, msg.sender, amountOwned);
    }
    // if profitable pay profits to payer
    if (amountOutV3 > amountOwned) {
      uint256 profit = LowGasSafeMath.sub(amountOutV3, amountOwned);
      TransferHelper.safeApprove(decoded.tokenIn, address(this), profit);
      TransferHelper.safeTransfer(decoded.tokenIn, decoded.payer, profit);
    }

  }

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
