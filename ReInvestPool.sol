// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./interface/iswap.sol";
import "./Third.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

// MasterChef is the master of RIT. He can make RIT and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once RIT is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract ReInvestPool is Third {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IUniswapV2Router02 router;
    // Info of each uRIT.
    struct URITInfo {
        uint256 amount;     // How many LP tokens the uRIT has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLpDebt; // 已经分的lp利息.
        uint256 lockTime;
        //
        // We do some fancy math here. Basically, any point in time, the amount of RITs
        // entitled to a uRIT but is pending to be distributed is:
        //
        //   pending reward = (uRIT.amount * pool.accRITPerShare) - uRIT.rewardDebt
        //
        // Whenever a uRIT deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRITPerShare` (and `lastRewardBlock`) gets updated.
        //   2. URIT receives the pending reward sent to his/her address.
        //   3. URIT's `amount` gets updated.
        //   4. URIT's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. RITs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that RITs distribution occurs.
        uint256 accRITPerShare; // Accumulated RITs per share, times 1e12. See below.
        uint256 minAMount;
        uint256 maxAMount;
        ERC20 rewardToken;
        uint256 pid;
        uint256 lpSupply;
        uint256 deposit_fee; // 1/10000
        uint256 withdraw_fee; // 1/10000
        uint256 allWithdrawReward;
    }
    uint256 public baseReward = 100000000;
    ISwap public thirdPool;
    // The RIT TOKEN!
    Common public rit;
    // Dev address.
    address public devaddr;
    // Fee address.
    address public feeaddr;
    // RIT tokens created per block.
    uint256 public RITPerBlock;
    // Bonus muliplier for early RIT makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each uRIT that stakes LP tokens.
    mapping (uint256 => mapping (address => URITInfo)) public uRITInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    uint256 public fee = 20; // 30% of profit
    uint256 public feeBase = 100; // 1% of profit

    event Deposit(address indexed uRIT, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed uRIT, uint256 indexed pid, uint256 amount);
    event ReInvest(uint256 indexed pid);
    event SetDev(address indexed devAddress);
    event SetFee(address indexed feeAddress);
    event SetRITPerBlock(uint256 _RITPerBlock);
    event SetPool(uint256 pid ,address lpaddr,uint256 point,uint256 min,uint256 max);
    constructor(
        Common _rit,
        address _feeaddr,
        address _devaddr,
        uint256 _RITPerBlock,
        IUniswapV2Router02 _router,
        ISwap _pool
    ) public {
        rit = _rit;
        feeaddr = _feeaddr;
        devaddr = _devaddr;
        RITPerBlock = _RITPerBlock;
        router = _router;
        thirdPool = _pool;
        initRouters();
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setBaseReward(uint256 _base) public onlyOwner {
        baseReward = _base;
    }

    function setRITPerBlock(uint256 _RITPerBlock) public onlyOwner {
        RITPerBlock = _RITPerBlock;
        emit SetRITPerBlock(_RITPerBlock);
    }

    function setFee(uint256 _fee) public onlyOwner {
        require(_fee <=30,"fee can not more than 30%");
        fee = _fee;
    }

    function GetPoolInfo(uint256 id) external view returns (PoolInfo memory) {
        return poolInfo[id];
    }

    function GetURITInfo(uint256 id,address addr) external view returns (URITInfo memory) {
        return uRITInfo[id][addr];
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _pid,uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate,uint256 _min,uint256 _max,uint256 _deposit_fee,uint256 _withdraw_fee,ERC20 _rewardToken) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        require(_deposit_fee <=30,"fee can not more than 3%");
        require(_withdraw_fee <=30,"fee can not more than 3%");
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRITPerShare: 0,
            minAMount:_min,
            maxAMount:_max,
            rewardToken:_rewardToken,
            pid:_pid,
            lpSupply:0,
            deposit_fee:_deposit_fee,
            withdraw_fee:_withdraw_fee,
            allWithdrawReward:0
        }));
        approve(poolInfo[poolInfo.length-1]);
        emit SetPool(poolInfo.length-1 , address(_lpToken), _allocPoint, _min, _max);
    }

    // Update the given pool's RIT allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate,uint256 _min,uint256 _max,uint256 _deposit_fee,uint256 _withdraw_fee) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        require(_deposit_fee <=30,"fee can not more than 3%");
        require(_withdraw_fee <=30,"fee can not more than 3%");
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].minAMount = _min;
        poolInfo[_pid].maxAMount = _max;
        poolInfo[_pid].deposit_fee = _deposit_fee;
        poolInfo[_pid].withdraw_fee = _withdraw_fee;
        emit SetPool(_pid , address(poolInfo[_pid].lpToken), _allocPoint, _min, _max);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending RITs on frontend.
    function pending(uint256 _pid, address _uRIT) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][_uRIT];
        uint256 accRITPerShare = pool.accRITPerShare;
        uint256 lpSupply = pool.lpSupply;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 RITReward = multiplier.mul(RITPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRITPerShare = accRITPerShare.add(RITReward.mul(1e12).div(lpSupply));
        }
        return uRIT.amount.mul(accRITPerShare).div(1e12).sub(uRIT.rewardDebt);
    }

       // View function to see pending RITs on frontend.
    function rewardLp(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][_user];
        if(thirdPool.userInfo(pool.pid, address(this)).amount <= 0){
            return 0;
        }
        uint256 ba = getWithdrawBalance(_pid, userShares[_pid][_user], thirdPool.userInfo(pool.pid, address(this)).amount);
        if(ba > uRIT.amount){
            return ba.sub(uRIT.amount);
        }
        return 0;
    }

    // View function to see pending RITs on frontend.
        // View function to see pending RITs on frontend.
    function allRewardLp(uint256 _pid) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        if(thirdPool.userInfo(pool.pid, address(this)).amount<=pool.lpSupply){
            return 0;
        }
        return pool.allWithdrawReward.add(thirdPool.userInfo(pool.pid, address(this)).amount.sub(pool.lpSupply));
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid,0,true);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid,uint256 _amount,bool isAdd) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        pool.lpSupply = isAdd ? pool.lpSupply.add(_amount) : pool.lpSupply.sub(_amount);
        if (pool.lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 RITReward = multiplier.mul(RITPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        rit.mint(address(this), RITReward); // Liquidity reward
        pool.accRITPerShare = pool.accRITPerShare.add(RITReward.mul(1e12).div(pool.lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for RIT allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(pause==0,'can not execute');
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][msg.sender];
        updatePool(_pid, 0, true);
        harvest(_pid);// 剩余利息进行复投
        uint256 pendingT = uRIT.amount.mul(pool.accRITPerShare).div(1e12).sub(uRIT.rewardDebt);
        if(pendingT > 0) {
            safeRITTransfer(msg.sender, pendingT);
        }
        if(_amount > 0) { // 
            // 先将金额抵押到合约
            if(pool.deposit_fee > 0){
                uint256 feeR = _amount.mul(pool.deposit_fee).div(10000);
                pool.lpToken.safeTransferFrom(address(msg.sender), devaddr, feeR);
                _amount = _amount.sub(feeR);
            }
            uint256 _before = thirdPool.userInfo(pool.pid,address(this)).amount;
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            thirdPool.deposit(pool.pid, _amount);
            uRIT.amount = uRIT.amount.add(_amount);

            if (pool.minAMount > 0 && uRIT.amount < pool.minAMount){
                revert("amount is too low");
            }
            if (pool.maxAMount > 0 && uRIT.amount > pool.maxAMount){
                revert("amount is too high");
            }
            uint256 _after = thirdPool.userInfo(pool.pid,address(this)).amount;
            pool.lpSupply = pool.lpSupply.add(_amount);
            _mint(_pid, _after.sub(_before), msg.sender, _before);
        }
        uRIT.rewardDebt = uRIT.amount.mul(pool.accRITPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // execute when only bug occur
    function safeWithdraw(uint256 _pid) public onlyOwner{
        require(pause==1,'can not execute');
        PoolInfo storage pool = poolInfo[_pid];
        thirdPool.withdraw(pool.pid, pool.lpSupply);
        pool.lpToken.safeTransfer(address(msg.sender), pool.lpSupply);
        uint256 ba = pool.rewardToken.balanceOf(address(this));
        // 
        if(ba<=0){
            return;
        }
        pool.rewardToken.transfer(devaddr,ba);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(pause==0,'can not execute');
        PoolInfo storage pool = poolInfo[_pid];
        URITInfo storage uRIT = uRITInfo[_pid][msg.sender];
        require(uRIT.amount >= _amount, "withdraw: not good");
        updatePool(_pid, 0, false);
        
        uint256 pendingT = uRIT.amount.mul(pool.accRITPerShare).div(1e12).sub(uRIT.rewardDebt);
        if(pendingT > 0) {
            safeRITTransfer(msg.sender, pendingT);
        }
        if(_amount > 0) {
            uint256 fene = thirdPool.userInfo(pool.pid,address(this)).amount;
            uint256 _shares = getWithdrawShares(_pid, _amount, msg.sender, uRIT.amount);
            uint256 should_withdraw = getWithdrawBalance(_pid, _shares, fene);
            pool.lpSupply = pool.lpSupply.sub(_amount);
            uRIT.amount = uRIT.amount.sub(_amount);
            thirdPool.withdraw(pool.pid, should_withdraw); // 
            if(pool.withdraw_fee>0){
                uint256 needFee = _amount.mul(pool.withdraw_fee).div(10000);      
                _amount = _amount.sub(needFee);
                pool.lpToken.safeTransfer(devaddr, needFee);
            }
            // 
            safeLpTransfer(_pid,address(msg.sender),_amount);
            _burn(_pid, _shares, msg.sender);
        }
        harvest(_pid);
        //
        uRIT.rewardDebt = uRIT.amount.mul(pool.accRITPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

        // Safe RIT transfer function, just in case if rounding error causes pool to not have enough RITs.
    function safeLpTransfer(uint256 _pid,address _to, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 RITBal = pool.lpToken.balanceOf(address(this));
        if(RITBal>_amount){
            pool.allWithdrawReward = pool.allWithdrawReward.add(RITBal.sub(_amount));
        }
        pool.lpToken.transfer(_to, RITBal);
    }

    function approve(PoolInfo memory pool) private {
        pool.rewardToken.approve(address(router),uint256(-1));
        address token0 = IUniswapV2Pair(address(pool.lpToken)).token0();
        address token1 = IUniswapV2Pair(address(pool.lpToken)).token1();
        IERC20(token0).approve(address(router),uint256(-1));
        IERC20(token1).approve(address(router),uint256(-1));
        pool.lpToken.approve(address(thirdPool), uint256(-1));
    }

    // 
    function calcProfit(uint256 _pid) private{
        PoolInfo storage pool = poolInfo[_pid];
        thirdPool.deposit(pool.pid, 0); // 
        uint256 ba = pool.rewardToken.balanceOf(address(this));
        if(ba<baseReward){
            return;
        }
        // pool.rewardToken.transfer(devaddr,ba);
        uint256 profitFee = ba.mul(fee).div(feeBase);
        pool.rewardToken.transfer(feeaddr,profitFee);
        ba = ba.sub(profitFee);
        uint256 half = ba.div(2);
        ba = ba.sub(half);
        if(half<=0 || ba<=0){
            return;
        }
        
        address token0 = IUniswapV2Pair(address(pool.lpToken)).token0();
        if(token0 != address(pool.rewardToken)){ // 
            swap(router,address(pool.rewardToken),token0,half);
        }

        address token1 = IUniswapV2Pair(address(pool.lpToken)).token1();
        
        if(token1 != address(pool.rewardToken)){ // 
            swap(router,address(pool.rewardToken),token1,ba);
        }
       
        uint256 token0Ba = IERC20(token0).balanceOf(address(this));
        uint256 token1Ba = IERC20(token1).balanceOf(address(this));
        if( token0Ba <= 0 || token1Ba <= 0 ){ // 没有余额
            return;
        }
        // IERC20(token0).transfer(devaddr,IERC20(token0).balanceOf(address(this)));
        // IERC20(token1).transfer(devaddr,IERC20(token1).balanceOf(address(this)));
        // return;
        (uint256 t0,uint256 t1,) = IUniswapV2Pair(address(pool.lpToken)).getReserves();
        if( t0<=0 || t1<=0 ){ // 没有流动性
            return;
        }
        uint256 out=0;
        uint256 liqui=0;
        if (t0.mul(token1Ba)>token0Ba.mul(t1)){
        
            out = token0Ba.mul(t1).div(t0);
            if(out <= 0){
                return;
            }
            
            (,,liqui) = router.addLiquidity(token0, token1, token0Ba, out, 0, 0, address(this), now.add(1800));
        } else{ //
            out = token1Ba.mul(t0).div(t1);
            if(out <= 0){
                return;
            }
            (,,liqui) = router.addLiquidity(token0, token1, out, token1Ba, 0, 0, address(this), now.add(1800));
        }
        futou(pool); // 
    }

    function futou(PoolInfo memory pool) private {
        uint256 ba = pool.lpToken.balanceOf(address(this));
        if(ba<=0){
            return;
        }
        if(pool.lpSupply<=0){
            pool.lpToken.transfer(feeaddr,ba);
            return;
        }
        // pool.lpToken.transfer(devaddr,ba);
        thirdPool.deposit(pool.pid,ba);
    }


    // auto reinvest
    function harvest(uint256 _pid) public {
        calcProfit(_pid); // 
        emit ReInvest(_pid);
    }

    // Safe RIT transfer function, just in case if rounding error causes pool to not have enough RITs.
    function safeRITTransfer(address _to, uint256 _amount) internal {
        uint256 RITBal = rit.balanceOf(address(this));
        if(RITBal<=0){
            return;
        }
        if (_amount > RITBal) {
            rit.transfer(_to, RITBal);
        } else {
            rit.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "_devaddr is address(0)");
        devaddr = _devaddr;
        emit SetDev(_devaddr);
    }

    // Update fee address by the previous dev.
    function setFeeAddr(address _feeaddr) public {
        require(msg.sender == feeaddr, "fee: wut?");
        require(_feeaddr != address(0), "_feeaddr is address(0)");
        feeaddr = _feeaddr;
        emit SetFee(_feeaddr);
    }
}
