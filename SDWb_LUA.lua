local Page0 = {
    work_mode = 0, --PWM=0/RPM=1 默认为0
    grain_full_flag = 0,
    grain_empty_flag = 0,
    hook_lock_flag = 0,
    hook_unlock_flag = 0,
    light1_flag = 0,
    light2_flag = 0,
    dO1_flag = 0,
    dO2_flag = 0,
    left_filter_angle = 0,
    right_filter_angle = 0,
    left_fan_speed = 0,
    right_fan_speed = 0,
    PWM_set = 0,
    left_fan_speed_set = 0
}



local send_data = {}
local temp_data = {}
local recv_data = {}
local can_id = {}
local can_data = {}
local pic_data = {}
local reg_data = {}


-- ====== 初始化函数 ======
function callback_init()
    -- 设置串口0工作模式：115200波特率，8N1格式
    com_set_work_mode(0, 1, 921600, 4)

    -- com_set_work_mode(1,0,115200,4)
  
    com_set_debug_print(0)
   
    -- -- 启动50ms定时器用于数据更新
    vgus_timer_start(0, 1, 0, 300)
end

function callback_timer(timer_id)
	if timer_id == 0 then
        --can_send()
        screen_update()
    end
end

-- ====== 触摸事件处理 ======
function callback_touch(pic_id, key_code, touch_state)
    if pic_id == 0 and key_code == 1 and touch_state == 2 then
      Page0.light1_flag = vgus_vp_var_read(0x0154,3)
      can_send()
    end
    if pic_id == 0 and key_code == 2 and touch_state == 2 then
      Page0.light2_flag = vgus_vp_var_read(0x0155,3)
      can_send()
    end
    if pic_id == 0 and key_code == 3 and touch_state == 2 then
      Page0.dO1_flag = vgus_vp_var_read(0x0156,3)
      can_send()
    end
    if pic_id == 0 and key_code == 4 and touch_state == 2 then
      Page0.dO2_flag = vgus_vp_var_read(0x0157,3)
      can_send()
    end
    if pic_id == 0 and key_code == 5 and touch_state == 2 then
      Page0.PWM_set = vgus_vp_var_read(0x0106,5)
      Page0.left_fan_speed_set = vgus_vp_var_write(0x0107,5,0x0000)
      Page0.work_mode = 0
      can_send()
    end
    if pic_id == 0 and key_code == 6 and touch_state == 2 then
      Page0.PWM_set = vgus_vp_var_write(0x0106,5,0x0000)
      Page0.left_fan_speed_set = vgus_vp_var_read(0x0107,5)
      Page0.work_mode = 1
      can_send()
    end
end

local Pro_data = {}
local Pro_data_len=0
local len=0
local read_len=0
local recv_len=0
local uart_data={}
local total_len=0

--====== 串口回调 ======
function callback_uart(com_num, recv_len)
    -- 1. 从串口缓冲区读取接收到的数据
    read_len = com_data_read(com_num, recv_len, uart_data)
    
    -- 2. 将本次读取的字节数显示在屏幕上(写入变量0xE000)
    vgus_vp_var_write(0xE000, 6, read_len)
    
    -- 3. 更新总接收字节数统计(写入变量0xE100)
    total_len = total_len + read_len
    vgus_vp_var_write(0x100, 6, total_len)
    
    -- 4. 仅处理串口0的数据
    if com_num == 0 then
        -- 初始化局部变量
        len = 0
        
        -- 5. 循环处理所有接收到的字节
        while( len < read_len ) do
            -- 6. 移动数据处理指针
            len = len + 1
            
            -- 7. 增加协议数据长度计数器
            Pro_data_len = Pro_data_len + 1
            
            -- 8. 将当前字节添加到协议数据缓冲区
            Pro_data[Pro_data_len] = uart_data[len]
            
            -- 9. 当接收到的数据达到完整一帧的长度(13字节)
            if Pro_data_len == 13 then
                -- 10. 检查帧头是否正确(0xAA)
                if Pro_data[1] == 0xAA then
                    -- 11. 提取CAN ID(4字节)
                    can_id[1] = Pro_data[2]
                    can_id[2] = Pro_data[3]
                    can_id[3] = Pro_data[4]
                    can_id[4] = Pro_data[5]
                    
                    -- 12. 提取CAN数据(8字节)
                    can_data[1] = Pro_data[6]
                    can_data[2] = Pro_data[7]
                    can_data[3] = Pro_data[8]
                    can_data[4] = Pro_data[9]
                    can_data[5] = Pro_data[10]
                    can_data[6] = Pro_data[11]
                    can_data[7] = Pro_data[12]
                    can_data[8] = Pro_data[13]
                    
                    -- 13. 调用数据处理函数
                    receive_data_prosess(can_id, can_data)
                    
                    -- 14. 重置协议数据长度计数器
                    Pro_data_len = 0
                else
                    -- 15. 帧头无效时的处理: 滑动窗口算法
                    for i = 1, 12 do
                        Pro_data[i] = Pro_data[i+1]
                    end
                    
                    -- 16. 设置协议数据长度为12(保留最后12个字节)
                    Pro_data_len = 12
                end
            end
        end
    end
end

function receive_data_prosess(can_id,can_data)
	can_state = 0
	if can_id[1] == 0x19 and can_id[2] == 0xC1 and can_id[3] == 0xA3 and can_id[4] == 0xA1 then
    -- 1. 解析左筛面角度（Data0-Data1）
    Page0.left_filter_angle = can_data[1] * 0x100 + can_data[2]  -- 组合高低字节
    -- 电压转角度: 0-65535 -> 0-360度
    Page0.left_filter_angle = Page0.left_filter_angle * 360 / 5000
    
    -- 2. 解析左风机转速（Data2-Data3）
    Page0.left_fan_speed = can_data[3] * 0x100 + can_data[4]  -- 组合高低字节
    
    -- -- 3. 解析状态位（Data7）
    local status_byte = can_data[8]
    -- -- 粮箱满状态 (bit0)
    Page0.grain_full_flag = status_byte & 0x01  -- bit0
    -- -- 粮箱空状态 (bit1)
    Page0.grain_empty_flag = ( status_byte >> 1 )& 0x01  -- bit1
	end

    if can_id[1] == 0x19 and can_id[2] == 0xC1 and can_id[3] == 0xA3 and can_id[4] == 0xA2 then
    -- 1. 解析右筛面角度（Data0-Data1）
    Page0.right_filter_angle = can_data[1] * 0x100 + can_data[2]  -- 组合高低字节
    -- 电流转角度: 4-20mA -> 0-360度
    Page0.right_filter_angle = (Page0.right_filter_angle - 4) * 22.5
    
    -- 2. 解析右风机转速（Data2-Data3）
    Page0.right_fan_speed = can_data[3] * 0x100 + can_data[4]  -- 组合高低字节
    
    -- -- 3. 解析状态位（Data7）
    local status_byte_recv2 = can_data[8]
    -- -- 挂钩锁定状态 (bit0)
    Page0.hook_lock_flag = status_byte_recv2 & 0x01  -- bit0
    -- -- 挂钩解锁状态 (bit1)
    Page0.hook_unlock_flag = ( status_byte_recv2 >> 1 )& 0x01  -- bit1
	end
end

function can_send()
    local byte = 
        (Page0.work_mode * 128) +  -- 第7位 (最高位 2^7)
        (Page0.light2_flag * 8) +          -- 第3位 (2^3)
        (Page0.light1_flag * 4) +          -- 第2位 (2^2)
        (Page0.dO2_flag * 2) +       -- 第1位 (2^1)
        Page0.dO1_flag               -- 第0位 (2^0 最低位)

    -- 构建协议数据包
        send_data = {0xAA,0x19,0xC1,0xA1,0xA3}  -- 帧头 (5字节)
        
        -- 数据包正文 (8字节)
        -- Data[0] 和 Data[1]: PWM设置值 (16位，小端格式)
        send_data[6] = (Page0.PWM_set >> 8) & 0xFF   -- 高字节 (Data[0])
        send_data[7] = Page0.PWM_set & 0xFF           -- 低字节 (Data[1])
        
        -- Data[2] 和 Data[3]: 左风机设定转速 (16位，小端格式)
        send_data[8] = (Page0.left_fan_speed_set >> 8) & 0xFF  -- 高字节 (Data[2])
        send_data[9] = Page0.left_fan_speed_set & 0xFF         -- 低字节 (Data[3])
        
        send_data[10] = 0x00
        send_data[11] = 0x00
        send_data[12] = 0x00
        
        send_data[13] = byte & 0xFF
        
        -- 通过串口0发送数据包
        com_data_send(0, 13, send_data)
        send_data = {}

end

-- function can_receive()
    
-- end

function screen_update()
    -- =====状态标志位更新=====
    if Page0.grain_full_flag == 1 then
        vgus_vp_var_write(0x0150,3,1)  -- 粮箱满
    else
        vgus_vp_var_write(0x0150,3,0)  -- 粮箱不满
    end
    if Page0.grain_empty_flag == 1 then
        vgus_vp_var_write(0x0151,3,1)  -- 粮箱空
    else
        vgus_vp_var_write(0x0151,3,0)  -- 粮箱不空
    end
    if Page0.hook_lock_flag == 1 then
        vgus_vp_var_write(0x0152,3,1)  -- 挂钩锁定
    else
        vgus_vp_var_write(0x0152,3,0)  -- 挂钩未锁定
    end
    if Page0.hook_unlock_flag == 1 then
        vgus_vp_var_write(0x0153,3,1)  -- 挂钩解锁
    else
        vgus_vp_var_write(0x0153,3,0)  -- 挂钩未解锁
    end
    -- =====变量显示更新=======
    vgus_vp_var_write(0x010E,5,Page0.left_fan_speed)
    vgus_vp_var_write(0x0102,5,Page0.left_filter_angle)
end

