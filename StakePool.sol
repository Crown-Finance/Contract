// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./interface/icustom.sol";
import "./Third.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
// MasterChef is the master of REWARD. He can make REWARD and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once REWARD is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract StakePool is Third {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IUniswapV2Router02 router;
    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of REWARDs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accREWARDPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accREWARDPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. REWARDs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that REWARDs distribution occurs.
        uint256 accREWARDPerShare; // Accumulated REWARDs per share, times 1e12. See below.
        uint256 minAMount;
        uint256 maxAMount;
        uint256 deposit_fee; // 1/10000
        uint256 withdraw_fee; // 1/10000
        ICustom lend; // 1/10000
        IERC20 rewardToken; // 1/10000
        uint256 lpSupply;
        uint256 allWithdrawReward;
    }

    // The REWARD TOKEN!
    Common public REWARD;
    // Fee address.
    address public feeaddr;
    // Dev address.
    address public devaddr;
    // Operation address.
    address public operationaddr;
    // Fund address.
    address public fundaddr;
    // REWARD tokens created per block.
    uint256 public REWARDPerBlock;
    // Bonus muliplier for early REWARD makers.
    uint256 public LockMulti = 1;
    uint256 public LockTime = 30 days;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDev(address indexed devAddress);
    event SetREWARDPerBlock(uint256 _REWARDPerBlock);
    event SetMigrator(address _migrator);
    event SetOperation(address _operation);
    event SetFund(address _fund);
    event SetInstitution(address _institution);
    event SetFee(address _feeaddr);
    event SetPool(uint256 pid ,address lpaddr,uint256 point,uint256 min,uint256 max);
    constructor(
        Common _REWARD,
        address _feeaddr,
        address _devaddr,
        address _operationaddr,
        address _fundaddr,
        uint256 _REWARDPerBlock,
        uint256 _LockMulti,
        IUniswapV2Router02 _router
    ) public {
        REWARD = _REWARD;
        devaddr = _devaddr;
        feeaddr = _feeaddr;
        REWARDPerBlock = _REWARDPerBlock;
        operationaddr = _operationaddr;
        fundaddr = _fundaddr;
        router = _router;
        LockMulti = _LockMulti;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setCbay(Common _cbay) public {
        REWARD = _cbay;
    }


    function setREWARDPerBlock(uint256 _REWARDPerBlock) public onlyOwner {
        REWARDPerBlock = _REWARDPerBlock;
        emit SetREWARDPerBlock(_REWARDPerBlock);
    }

    function setLockMulti(uint256 _lockMulti) public onlyOwner {
        LockMulti = _lockMulti;
    }

    function GetPoolInfo(uint256 id) external view returns (PoolInfo memory) {
        return poolInfo[id];
    }

    function GetUserInfo(uint256 id,address addr) external view returns (UserInfo memory) {
        return userInfo[id][addr];
    }

    function balanceOfUnderlying(PoolInfo memory pool) public view returns (uint256){
        return pool.lend.updatedSupplyOf(address(this));
    }

    // View function to see pending RITs on frontend.
    function rewardLp(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage uRIT = userInfo[_pid][_user];
        uint256 thirdAllBalance = balanceOfUnderlying(pool);
        if(thirdAllBalance <= 0){
            return 0;
        }
        uint256 ba = uRIT.amount.mul(thirdAllBalance).div(pool.lpSupply);
        if(ba > uRIT.amount){
            return ba.sub(uRIT.amount);
        }
        return 0;
    }

    // View function to see pending RITs on frontend.
    function allRewardLp(uint256 _pid) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 thirdAllBalance = balanceOfUnderlying(pool);
        if(thirdAllBalance <= pool.lpSupply){
            return 0;
        }
        return pool.allWithdrawReward.add(thirdAllBalance.sub(pool.lpSupply));
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate,uint256 _min,uint256 _max,uint256 _deposit_fee,uint256 _withdraw_fee,ICustom _lend,IERC20 _rewardToken) public onlyOwner {
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
            accREWARDPerShare: 0,
            minAMount:_min,
            maxAMount:_max,
            deposit_fee : _deposit_fee,
            withdraw_fee : _withdraw_fee,
            lend: _lend,
            rewardToken: _rewardToken,
            lpSupply: 0,
            allWithdrawReward: 0
        }));
        approve(poolInfo[poolInfo.length-1]);
        emit SetPool(poolInfo.length-1 , address(_lpToken), _allocPoint, _min, _max);
    }

    function approve(PoolInfo memory pool) private {
        if(address(pool.lend) != address(0) ){
            if(address(pool.rewardToken) != address(0)){
                pool.rewardToken.approve(address(router),uint256(-1));
                pool.rewardToken.approve(address(pool.lend),uint256(-1));
            }
            pool.lpToken.approve(address(pool.lend), uint256(-1));
        }
    }

    // Update the given pool's REWARD allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate,uint256 _min,uint256 _max,uint256 _deposit_fee,uint256 _withdraw_fee,ICustom _lend,IERC20 _rewardToken) public onlyOwner {
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
        poolInfo[_pid].lend = _lend;
        poolInfo[_pid].rewardToken = _rewardToken;
        approve(poolInfo[_pid]);
        emit SetPool(_pid , address(poolInfo[_pid].lpToken), _allocPoint, _min, _max);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

   
    function getApy(uint256 _pid) public view returns (uint256) {
        uint256 yearCount = REWARDPerBlock.mul(86400).div(3).mul(365);
        return yearCount.div(getTvl(_pid));
    }


    function getTvl(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        (uint256 t1,uint256 t2,) = IUniswapV2Pair(address(pool.lpToken)).getReserves();
        address token0 = IUniswapV2Pair(address(pool.lpToken)).token0();
        uint256 allCount = 0;
        if(token0==address(REWARD)){ // 总成本
            allCount = t1.mul(2);
        } else{
            allCount = t2.mul(2);
        }
        uint256 lpSupply = pool.lpSupply;
        uint256 totalSupply = pool.lpToken.totalSupply();
        return allCount.mul(lpSupply).div(totalSupply);
    }

    // View function to see pending REWARDs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accREWARDPerShare = pool.accREWARDPerShare;
        uint256 lpSupply = pool.lpSupply;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 REWARDReward = multiplier.mul(REWARDPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accREWARDPerShare = accREWARDPerShare.add(REWARDReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accREWARDPerShare).div(1e12).sub(user.rewardDebt);
        return pending.div(LockMulti);
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
        pool.lpSupply = isAdd ? pool.lpSupply.add(_amount) : pool.lpSupply.sub(_amount) ;
        if (pool.lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 REWARDReward = multiplier.mul(REWARDPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 miningReward = REWARDReward;
        uint256 devReward = miningReward.mul(1875);
        REWARD.mint(devaddr, devReward.div(10000)); // 15% Development
        uint256 oprReward = miningReward.mul(375);
        REWARD.mint(operationaddr, oprReward.div(10000)); // 3% Operation
        REWARD.mint(address(this), REWARDReward); // Liquidity reward
        pool.accREWARDPerShare = pool.accREWARDPerShare.add(REWARDReward.mul(1e12).div(pool.lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for REWARD allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(pause==0,'can not execute');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid,0,true);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accREWARDPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeREWARDTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            if(pool.deposit_fee > 0){
                uint256 feeR = _amount.mul(pool.deposit_fee).div(10000);
                pool.lpToken.safeTransferFrom(address(msg.sender), devaddr, feeR);
                _amount = _amount.sub(feeR);
            }
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            if (pool.minAMount > 0 && user.amount < pool.minAMount){
                revert("amount is too low");
            }
            if (pool.maxAMount > 0 && user.amount > pool.maxAMount){
                revert("amount is too high");
            }
            if(address(pool.lend) != address(0)){
                depositLend( pool, _amount);
            }
            pool.lpSupply = pool.lpSupply.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accREWARDPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function depositLend(PoolInfo memory pool,uint256 _amount) private {
        if(_amount<=0){
            return;
        }
        pool.lend.mint(_amount);
    }

    function withdrawLend(uint256 _pid,uint256 _amount) private returns(uint256){
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.lpSupply>0,"none pool.lpSupply");
        uint256 allAmount = pool.lend.updatedSupplyOf(address(this));
        uint256 shouldAmount = _amount.mul(allAmount).div(pool.lpSupply);
         if(shouldAmount>_amount){
            pool.allWithdrawReward = pool.allWithdrawReward.add(shouldAmount.sub(_amount));
        }
        // 
        pool.lend.redeem(shouldAmount);
        return shouldAmount;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid,0,false);
        uint256 pending = user.amount.mul(pool.accREWARDPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeREWARDTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            uint256 shouldAmount = _amount;
            if(address(pool.lend) != address(0)){
                shouldAmount = withdrawLend(_pid,_amount);
            }
            user.amount = user.amount.sub(_amount);
            uint256 originAmount = _amount;
            if(pool.withdraw_fee>0){
                uint256 fee = _amount.mul(pool.withdraw_fee).div(10000);      
                _amount = _amount.sub(fee);
                pool.lpToken.safeTransfer(devaddr, fee);
            }
            safeLpTransfer(pool,msg.sender,shouldAmount);
            pool.lpSupply = pool.lpSupply.sub(originAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accREWARDPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function safeLpTransfer(PoolInfo memory pool,address _to, uint256 _amount) internal {

        uint256 ba = pool.lpToken.balanceOf(address(this));
        
        if (_amount > ba) {
            pool.lpToken.transfer(_to, ba);
        } else {
            pool.lpToken.transfer(_to, _amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe REWARD transfer function, just in case if rounding error causes pool to not have enough REWARDs.
    function safeREWARDTransfer(address _to, uint256 _amount) internal {

        uint256 ba = REWARD.balanceOf(address(this));
        
        if (_amount > ba) {
            REWARD.transfer(_to, ba);
        } else {
            REWARD.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "_devaddr is address(0)");
        devaddr = _devaddr;
        emit SetDev(_devaddr);
    }

    // Update operation address by the previous operation.
    function operation(address _opaddr) public {
        require(msg.sender == operationaddr, "operation: wut?");
        require(_opaddr != address(0), "_opaddr is address(0)");
        operationaddr = _opaddr;
        emit SetOperation(_opaddr);
    }

    // Update fund address by the previous fund.
    function fund(address _fundaddr) public {
        require(msg.sender == fundaddr, "fund: wut?");
        require(_fundaddr != address(0), "_fundaddr is address(0)");
        fundaddr = _fundaddr;
        emit SetFund(_fundaddr);
    }

    // Update fee address by the previous institution.
    function setFee(address _feeaddr) public {
        require(msg.sender == feeaddr, "feeaddr: wut?");
        require(_feeaddr != address(0), "_feeaddr is address(0)");
        feeaddr = _feeaddr;
        emit SetFee(_feeaddr);
    }
}
