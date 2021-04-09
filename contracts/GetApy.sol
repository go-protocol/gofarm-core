pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";

interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IVault {
    function token() external view returns (address);
    function getPricePerFullShare() external view returns (uint256);
    function decimals() external view returns (uint8);
}

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

interface IGetVaultApy {
    function getTVLPrice(address[] memory _vaults)
        external
        view
        returns (uint256[] memory);
}

contract GetApy {
    using SafeMath for uint256;

    address public constant masterChef =
        0xb6e8Df513dD634Bc033CdB3099448269728e8deE;
    uint256 public constant GOTPerBlock = 0.003125 ether;
    uint256 public constant epochPeriod = 28800;

    address public constant GOT = 0xA7d5b5Dbc29ddef9871333AD2295B2E7D6F12391;
    address public constant GOC = 0x271B54EBe36005A7296894F819D626161C44825C;
    address public constant GOS = 0x3bb34419a8E7d5E5c68B400459A8eC1AFfe9c56E;
    address public constant HUSD = 0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    /// @notice USDT地址
    address public constant USDT = 0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public constant GOT_HUSD_LP =
        0x11d6a89Ce4Bb44138219ae11C1535F52E16B7Bd2;
    address public constant GOC_HUSD_LP =
        0xEe09490789564e22c9b6252a2419A57055957a47;
    address public constant GOS_HUSD_LP =
        0xdaDE2b002d135c5796f7cAAd544f9Bc043D05C9B;
    /// @notice MDEX路由地址
    address public constant uniRouter =
        0xED7d5F38C79115ca12fe6C0041abb22F0A06C300;

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

    /// @dev 获取价格
    function _getPriceOne(address _token) public view returns (uint256) {
        uint256 amountIn = 10**uint256(IVault(_token).decimals());
        if (_token == USDT) {
            return amountIn;
        } else {
            address[] memory path = new address[](2);
            path[0] = _token;
            path[1] = USDT;
            uint256[] memory amounts;
            amounts = Uni(uniRouter).getAmountsOut(amountIn, path);
            return amounts[1];
        }
    }

    function getVaultPrice(address vault) public view returns (uint256) {
        address token = IVault(vault).token();
        uint256 getPricePerFullShare = IVault(vault).getPricePerFullShare();
        uint256 decimals = uint256(IVault(token).decimals());
        uint256 price =
            IERC20(vault).balanceOf(masterChef)
            .mul(getPricePerFullShare)
            .mul(_getPriceOne(token))
            .div(10 ** decimals)
            .div(1e18);
        return price;
    }

    function getVaultApy(uint256 pid) public view returns (uint256) {
        (address lpToken, uint256 amount) = allocPerDay(pid);
        uint256 poolPrice = getVaultPrice(lpToken);
        return poolPrice > 0 ? amount.mul(getGOTPrice()).div(poolPrice) : 0;
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
            allPoolPrice[i] = i < 16
                ? getPoolPrice(lpToken)
                : getVaultPrice(lpToken);
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
            apys[i] = i < 16 ? poolApy(i) : getVaultApy(i);
        }
        return apys;
    }

    function getTvl() public view returns (uint256) {
        uint256 poolLength = IMasterChef(masterChef).poolLength();
        uint256 tvl = 0;
        for (uint256 i = 0; i < poolLength; i++) {
            (address lpToken, ) = allocPerDay(i);
            tvl = tvl.add(
                i < 16 ? getPoolPrice(lpToken) : getVaultPrice(lpToken)
            );
        }
        return tvl;
    }
}
