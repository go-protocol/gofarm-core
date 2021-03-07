// SPDX-License-Identifier: Anti-996
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";

interface IMasterChef {
    function getMultiplier(uint256 _from, uint256 _to)
        external
        view
        returns (uint256 multiplier);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accGOTPerShare
        );

    function totalAllocPoint() external view returns (uint256);

    function poolLength() external view returns (uint256);
}

contract GetApy {
    using SafeMath for uint256;

    address public constant masterChef =
        0xC9FAA89989bd6562dbc67f34F825028A79f4f1B1;
    uint256 public constant GOTPerBlock = 0.003125 ether;
    uint256 public constant epochPeriod = 28800;

    address public constant GOT = 0xA7d5b5Dbc29ddef9871333AD2295B2E7D6F12391;
    address public constant GOC = 0x271B54EBe36005A7296894F819D626161C44825C;
    address public constant GOS = 0x36b29B53c483bd00978D40126E614bb7e45d8354;
    address public constant HUSD = 0x0f548051B135fa8f7F6190cb78Fd13eCB544fEE6;
    address public constant GOT_HUSD_LP =
        0xC31b9f33fB2C54B789C263781CCEE9b23b747677;
    address public constant GOC_HUSD_LP =
        0x28BFcd3c234B710d93232B5e51a2e8b8a5bb9D2f;
    address public constant GOS_HUSD_LP =
        0xd0E8D781fAe230E3DA6e45ED881c99BA639cA400;

    function getGOTPrice() public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) =
            IUniswapV2Pair(GOT_HUSD_LP).getReserves();
        return (reserve0 * 10**28) / reserve1;
    }

    function getGOCPrice() public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) =
            IUniswapV2Pair(GOC_HUSD_LP).getReserves();
        return (reserve0 * 10**28) / reserve1;
    }

    function getGOSPrice() public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) =
            IUniswapV2Pair(GOS_HUSD_LP).getReserves();
        return (reserve0 * 10**28) / reserve1;
    }

    function allocPerDay(uint256 pid) public view returns (address, uint256) {
        (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, ) =
            IMasterChef(masterChef).poolInfo(pid);
        uint256 multiplier =
            IMasterChef(masterChef).getMultiplier(
                lastRewardBlock,
                lastRewardBlock + 1
            );
        uint256 totalAllocPoint = IMasterChef(masterChef).totalAllocPoint();
        uint256 amount =
            multiplier.mul(GOTPerBlock).mul(epochPeriod).mul(allocPoint).div(
                totalAllocPoint
            );
        return (lpToken, amount);
    }

    function getPoolPrice(address lpToken) public view returns (uint256) {
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        uint256 balanceOf = IERC20(lpToken).balanceOf(masterChef);
        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();

        (uint256 reserve0, uint256 reserve1, ) =
            IUniswapV2Pair(lpToken).getReserves();

        if (token0 == HUSD || token1 == HUSD) {
            uint256 reserve = token0 == HUSD ? reserve0 : reserve1;
            return reserve.mul(balanceOf).div(totalSupply).mul(2).mul(10**10);
        }
        if (token0 == GOT || token1 == GOT) {
            uint256 reserve = token0 == GOT ? reserve0 : reserve1;
            return
                reserve
                    .mul(balanceOf)
                    .div(totalSupply)
                    .mul(2)
                    .mul(getGOTPrice())
                    .div(10**18);
        }
        if (token0 == GOC || token1 == GOC) {
            uint256 reserve = token0 == GOC ? reserve0 : reserve1;
            return
                reserve
                    .mul(balanceOf)
                    .div(totalSupply)
                    .mul(2)
                    .mul(getGOCPrice())
                    .div(10**18);
        }
        if (token0 == GOS || token1 == GOS) {
            uint256 reserve = token0 == GOS ? reserve0 : reserve1;
            return
                reserve
                    .mul(balanceOf)
                    .div(totalSupply)
                    .mul(2)
                    .mul(getGOSPrice())
                    .div(10**18);
        }
    }

    function poolApy(uint256 pid) public view returns (uint256) {
        (address lpToken, uint256 amount) = allocPerDay(pid);
        uint256 poolPrice = getPoolPrice(lpToken);

        return poolPrice > 0 ? amount.mul(getGOTPrice()).div(poolPrice) : 0;
    }

    function getAllPoolPrice() public view returns (uint256[] memory) {
        uint256 poolLength = IMasterChef(masterChef).poolLength();
        uint256[] memory allPoolPrice = new uint256[](poolLength);
        for (uint256 i = 0; i < poolLength; i++) {
            (address lpToken, ) = allocPerDay(i);
            allPoolPrice[i] = getPoolPrice(lpToken);
        }
        return allPoolPrice;
    }

    function getAllAlloc() public view returns (uint256[] memory) {
        uint256 poolLength = IMasterChef(masterChef).poolLength();
        uint256[] memory allAlloc = new uint256[](poolLength);
        for (uint256 i = 0; i < poolLength; i++) {
            (, uint256 amount) = allocPerDay(i);
            allAlloc[i] = amount;
        }
        return allAlloc;
    }

    function getAllApy() public view returns (uint256[] memory) {
        uint256 poolLength = IMasterChef(masterChef).poolLength();
        uint256[] memory apys = new uint256[](poolLength);
        for (uint256 i = 0; i < poolLength; i++) {
            apys[i] = poolApy(i);
        }
        return apys;
    }

    function getTvl() public view returns (uint256) {
        uint256 poolLength = IMasterChef(masterChef).poolLength();
        uint256 tvl = 0;
        for (uint256 i = 0; i < poolLength; i++) {
            (address lpToken, ) = allocPerDay(i);
            tvl = tvl.add(getPoolPrice(lpToken));
        }
        return tvl;
    }
}
