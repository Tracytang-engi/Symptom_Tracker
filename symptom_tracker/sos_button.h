/**
 * sos_button.h — SOS 按钮模块（头文件）
 *
 * 功能：检测 GPIO25 上的按钮长按，触发 SOS 事件。
 * 逻辑：按下超过 SOS_HOLD_MS（默认2秒）才算触发，防止误按。
 */

#pragma once  // 防止头文件被重复包含

// 初始化 SOS 按钮（设置引脚模式，在 setup() 里调用一次）
void SOS_init();

// 每次 loop() 调用，检测按钮状态（非阻塞，不用 delay）
// 返回 true = 本次循环触发了 SOS；false = 未触发
bool SOS_update();
