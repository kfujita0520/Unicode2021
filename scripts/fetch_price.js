// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const {BigNumber} = require("ethers");

async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');

    // We get the contract to deploy
    const UniFactory = await hre.ethers.getContractAt("IUniswapV2Factory", "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
    const WETH = await hre.ethers.getContractAt("IWETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    const BAT = await hre.ethers.getContractAt("IERC20", "0x0D8775F648430679A709E98d2b0Cb6250d2887EF");
    const ERC20 = await hre.ethers.getContractAt("IERC20", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    const UniRouterV2 = await hre.ethers.getContractAt("IUniswapV2Router02", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
    const Quoter = await hre.ethers.getContractAt("IQuoter", "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6");



    const [sender] = await hre.ethers.getSigners();

    let eth_amount = 42000000;
    let addresses = [WETH.address, BAT.address];

    let amounts = await UniRouterV2.getAmountsOut(eth_amount, addresses).catch(err => {
        console.log(err);
    });
    console.log('ETH V2: ' + amounts[0]);
    console.log('BAT V2: ' + amounts[1]);

    let bat_amount = await Quoter.quoteExactInputSingle(WETH.address, BAT.address, 3000, 0, eth_amount).catch(err => {
        console.log(err);
    });
    console.log('ETH V2: ' + eth_amount);
    console.log('BAT V2: ' + bat_amount);



    // let tx5 = await UniRouterV2.swapExactTokensForETH(51000000, 0, addresses2, sender.address, Date.now() + 1000000).catch(err => {
    //     console.log(err);
    // });
    // await tx5.wait();

    //await greeter.deployed();
    //console.log("Greeter deployed to:", greeter.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
