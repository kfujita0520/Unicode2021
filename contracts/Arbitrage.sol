pragma solidity > 0.6.6;

import './libraries/UniswapV2Library.sol';
import './interfaces/V2/IUniswapV2Router02.sol';
import './interfaces/V2/IUniswapV2Pair.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/V3/ISwapRouter.sol';
import './interfaces/V3/IUniswapV3Factory.sol';
import 'hardhat/console.sol';

contract Arbitrage {
  address public factoryV2;
  address public factoryV3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  uint constant deadline = 10 days;
  ISwapRouter public swapRouterV3;
  address public swapRouterV2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
  address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  enum Direction { V2ToV3, V3ToV2 }

  constructor(address _factoryV2, address _routerV3) public {
    factoryV2 = _factoryV2;
    swapRouterV3 = ISwapRouter(_routerV3);
  }

  function arbitrageV2ToV3(
    address input,
    address output,
    uint amountIn, //amountIn may not be needed
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



  function arbitrageV3ToV2(
    address input,
    address output,
    uint amountIn, //amountIn may not be needed
    uint amountOut
  ) external {
    console.log('startArbitrageV3toV2');
    address poolAddress = IUniswapV3Factory(factoryV3).getPool(input, output, 3000);
    require(poolAddress != address(0), 'This pool does not exist');
    console.log('Pool Address');
    console.log(poolAddress);



    //    address token0 = IUniswapV2Pair(pairAddress).token0();
    //
    //    (uint amount0, uint amount1) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
    //    //Specify only output amount and make inputAmount 0. input token will be returned in uniswapV2Call
    //    IUniswapV2Pair(pairAddress).swap(amount0, amount1, address(this), bytes('not empty'));


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

    //token is token acquired from V2 pair pool
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
}
