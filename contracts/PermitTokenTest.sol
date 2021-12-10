pragma solidity > 0.7.2;

import './libraries/UniswapV2Library.sol';
import './interfaces/V2/IUniswapV2Router02.sol';
import './interfaces/V2/IUniswapV2Pair.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2ERC20.sol';
import 'hardhat/console.sol';

contract PermitTokenTest {

    //address of the uniswap v2 router
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //address of WETH token.  This is needed because some times it is better to trade through WETH.
    //you might get a better price using WETH.
    //example trading from token A to WETH then WETH to token B might result in a better price
    address private constant WETH = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    address private constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 public DOMAIN_SEPARATOR;

    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(IUniswapV2ERC20(UNI).name())),
                keccak256(bytes('1')),
                chainId,
                UNI
            )
        );
        console.log(chainId);
    }


    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }


    function transferTest(address _tokenIn, uint256 _amountIn,  uint8 v, bytes32 r, bytes32 s) external {

        //first we need to transfer the amount in tokens from the msg.sender to this contract
        //this contract will have the amount of in tokens
        console.log('start permit');
        //IERC20(_tokenIn).approve(address(this), 1000000000000000);

        uint256 MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        //Unfortunately, this permit does not work and return "Uni::permit: unauthorized", even though heccak256 signature is identified
        //I guess Uniswap token implement some extra security layer which does not publicized in open source.
        IUniswapV2ERC20(_tokenIn).permit(msg.sender, address(this), _amountIn, MAX_INT, v, r, s);
        console.log('finish permit');

        //require(IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn), 'transferFrom failed.');


    }

    //test method to verify if keccak signature is identified to the requested one.
    function testPermit(address owner, uint value, uint8 v, bytes32 r, bytes32 s) external {
        //require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        console.logBytes32(DOMAIN_SEPARATOR);
        console.log(owner);
        console.log(address(this));
        uint256 MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(this), value, IUniswapV2ERC20(UNI).nonces(owner), MAX_INT))
            )
        );
        console.logBytes32(digest);
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        //_approve(owner, spender, value);//since this is test, actual approve is not required.
    }



}
