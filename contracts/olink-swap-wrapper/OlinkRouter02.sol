pragma solidity >=0.6.6;

import '../olink-swap-core/interfaces/IOlinkFactory.sol';
import '../olink-swap-lib/utils/TransferHelper.sol';

import './interfaces/IOlinkRouter02.sol';
import './libraries/OlinkLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract OlinkRouter02 is IOlinkRouter02 {
    using SafeMath for uint;

    address public owner;
    mapping(address => uint256) public ethBurnRatio;
    mapping(address => uint256) public tokenBurnRatio;
    mapping(address => uint256) public ethBurnOutRatio;
    mapping(address => uint256) public ethFundRatio;

    mapping(address => uint256) public tokenAddBurnRatio;
    mapping(address => uint256) public tokenBurnLimit;
    mapping(address => address) public tokenFund;

    uint256 public totalEthBurned;
    mapping(address => uint256) public tokenBurned;
    mapping(address => uint256) public ethBurned;
    mapping(address => bool) public whiteList;

    address payable public pubFund;

    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'OlinkRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;

        owner = msg.sender;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    modifier onlyOwner() {
	    require(msg.sender == owner);
	    _;
	}

	function setOwner(address ownerAddress) external onlyOwner {
		require(ownerAddress != address(0), "owner can't be null");
		owner = ownerAddress;
	}

	function setEthBurnRatio(address token, uint256 ratio) external onlyOwner {
		require(ratio < 100, "ratio can't be greater than 100");
		ethBurnRatio[token] = ratio;
	}

	function setTokenBurnRatio(address token, uint256 ratio) external onlyOwner {
		require(ratio < 100, "ratio can't be greater than 100");
		tokenBurnRatio[token] = ratio;
	}

	function setEthBurnOutRatio(address token, uint256 ratio) external onlyOwner {
		require(ratio < 100, "ratio can't be greater than 100");
		ethBurnOutRatio[token] = ratio;
	}

	function setEthFundRatio(address token, uint256 ratio) external onlyOwner {
		require(ratio < 100, "ratio can't be greater than 100");
		ethFundRatio[token] = ratio;
	}

	function setWhite(address addr, bool flag) external onlyOwner {
		whiteList[addr] = flag;
	}

	function setPubFund(address payable addr) external onlyOwner {
		pubFund = addr;
	}

	function setTokenAddBurnRatio(address token, uint256 ratio) external onlyOwner {
		tokenAddBurnRatio[token] = ratio;
	}

	function setTokenBurnLimit(address token, uint256 limit) external onlyOwner {
		tokenBurnLimit[token] = limit;
	}

	function setTokenFund(address token, address fund) external onlyOwner {
		tokenFund[token] = fund;
	}

	function getBurnedData(address token) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
		return (ethBurnRatio[token] + ethFundRatio[token], tokenBurnRatio[token], totalEthBurned, ethBurned[token], tokenBurned[token], ethBurnOutRatio[token], ethFundRatio[token]);
	}

    // **** For web ****
    function getReserves(address tokenA, address tokenB) external view returns(uint amountA, uint amountB) {
    	(amountA, amountB) = OlinkLibrary.getReserves(factory, tokenA, tokenB);
    }

    function getTotalSupply(address tokenA, address tokenB) external view returns(uint totalSupply) {
    	totalSupply = OlinkLibrary.getTotalSupply(factory, tokenA, tokenB);
    }

    function getLpBalance(address tokenA, address tokenB, address addr) external view returns(uint balance) {
    	balance = OlinkLibrary.getLpBalance(factory, tokenA, tokenB, addr);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IOlinkFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IOlinkFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = OlinkLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = OlinkLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'OlinkRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = OlinkLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'OlinkRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = OlinkLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IOlinkPair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = OlinkLibrary.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IOlinkPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);

        if (tokenAddBurnRatio[token] > 0) {
        	uint256 needBurn = amountToken * tokenAddBurnRatio[token] / 100;
        	if(needBurn + tokenBurned[token] <= tokenBurnLimit[token]) {
        		TransferHelper.safeTransferFrom(token, tokenFund[token], address(this), needBurn);
        		tokenBurned[token] += needBurn;
        	}
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = OlinkLibrary.pairFor(factory, tokenA, tokenB);
        IOlinkPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IOlinkPair(pair).burn(to);
        (address token0,) = OlinkLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'OlinkRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'OlinkRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = OlinkLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IOlinkPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = OlinkLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IOlinkPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = OlinkLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IOlinkPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = OlinkLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? OlinkLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IOlinkPair(OlinkLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = OlinkLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'OlinkRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OlinkLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = OlinkLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'OlinkRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OlinkLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'OlinkRouter: INVALID_PATH');

        if(!whiteList[msg.sender] && ethFundRatio[path[1]] > 0) {
        	pubFund.transfer(msg.value * ethFundRatio[path[1]] / 100);
        }
        if(!whiteList[msg.sender] && ethBurnRatio[path[1]] > 0) {
	        totalEthBurned += (msg.value * ethBurnRatio[path[1]] / 100);
	        ethBurned[path[1]] += (msg.value * ethBurnRatio[path[1]] / 100);
	    }

        uint256 ratio = (whiteList[msg.sender] ? 0 : ethBurnRatio[path[1]] + ethFundRatio[path[1]]);
        
        amounts = OlinkLibrary.getAmountsOut(factory, msg.value * (100 - ratio) / 100, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'OlinkRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(OlinkLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'OlinkRouter: INVALID_PATH');
        amounts = OlinkLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'OlinkRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OlinkLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'OlinkRouter: INVALID_PATH');
        uint256 ratio = (whiteList[msg.sender] ? 0 : tokenBurnRatio[path[0]]);
        tokenBurned[path[0]] += (amountIn * ratio / 100);
        amounts = OlinkLibrary.getAmountsOut(factory, amountIn * (100 - ratio) / 100, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'OlinkRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        if(ratio > 0) {
        	TransferHelper.safeTransferFrom(
	            path[0], msg.sender, address(this), amountIn * ratio / 100
	        );
        }

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OlinkLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        uint outRatio = (whiteList[msg.sender] ? 0 : ethBurnOutRatio[path[0]]);
        totalEthBurned += (amounts[amounts.length - 1] * outRatio / 100);
        ethBurned[path[0]] += (amounts[amounts.length - 1] * outRatio / 100);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1] * (100 - outRatio) / 100);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'OlinkRouter: INVALID_PATH');
        amounts = OlinkLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'OlinkRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(OlinkLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = OlinkLibrary.sortTokens(input, output);
            IOlinkPair pair = IOlinkPair(OlinkLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = OlinkLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? OlinkLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OlinkLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'OlinkRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'OlinkRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(OlinkLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'OlinkRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'OlinkRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OlinkLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'OlinkRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return OlinkLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return OlinkLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return OlinkLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return OlinkLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return OlinkLibrary.getAmountsIn(factory, amountOut, path);
    }
}
