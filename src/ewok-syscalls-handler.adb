--
-- Copyright 2018 The wookey project team <wookey@ssi.gouv.fr>
--   - Ryad     Benadjila
--   - Arnauld  Michelizza
--   - Mathieu  Renard
--   - Philippe Thierry
--   - Philippe Trebuchet
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
--     Unless required by applicable law or agreed to in writing, software
--     distributed under the License is distributed on an "AS IS" BASIS,
--     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--     See the License for the specific language governing permissions and
--     limitations under the License.
--
--

with ewok.tasks;        use ewok.tasks;
with ewok.tasks_shared; use ewok.tasks_shared;
with ewok.sched;
with ewok.sanitize;
with ewok.syscalls.cfg.dev;
with ewok.syscalls.cfg.gpio;
with ewok.syscalls.gettick;
with ewok.syscalls.init;
with ewok.syscalls.ipc;
with ewok.syscalls.lock;
with ewok.syscalls.log;
with ewok.syscalls.reset;
with ewok.syscalls.rng;
with ewok.syscalls.sleep;
with ewok.syscalls.yield;
with ewok.syscalls.exiting;
with ewok.syscalls.alarm;
with ewok.exported.interrupts;
   use type ewok.exported.interrupts.t_interrupt_config_access;
with ewok.debug;

#if CONFIG_KERNEL_DMA_ENABLE
with ewok.syscalls.dma;
#end if;

with m4.cpu.instructions;

package body ewok.syscalls.handler
   with spark_mode => off
is

   type t_task_access is access all ewok.tasks.t_task;

   function svc_handler
     (frame_a : t_stack_frame_access)
      return t_stack_frame_access
   is
      current_id     : constant t_task_id       := ewok.sched.current_task_id;
      current_a      : constant t_task_access   := ewok.tasks.tasks_list(current_id)'access;
      svc_params_a   : t_parameters_access      := NULL;
      svc            : t_svc;
   begin

      --
      -- We must save the frame pointer because synchronous syscall don't refer
      -- to the parameters on the stack indexed by 'frame_a' but to
      -- 'current_a' (they access 'frame_a' via 'current_a.all.ctx.frame_a'
      -- or 'current_a.all.isr_ctx.frame_a')
      --

      if current_a.all.mode = TASK_MODE_MAINTHREAD then
         current_a.all.ctx.frame_a := frame_a;
      else
         current_a.all.isr_ctx.frame_a := frame_a;
      end if;

      --
      -- Getting the svc number from the SVC instruction
      --

      declare
         inst : m4.cpu.instructions.t_svc_instruction
            with import, address => to_address (frame_a.all.PC - 2);
      begin
         if not inst.opcode'valid then
            raise program_error;
         end if;

         declare
            svc_type : t_svc with address => inst.svc_num'address;
         begin
            if not svc_type'valid then
               ewok.tasks.set_state
                 (current_id, TASK_MODE_MAINTHREAD, TASK_STATE_FAULT);
               set_return_value
                 (current_id, current_a.all.mode, SYS_E_DENIED);
               return frame_a;
            end if;
            svc := svc_type;
         end;
      end;

      --
      -- Getting svc parameters from caller's stack
      --

      if
         ewok.sanitize.is_range_in_data_slot
           (frame_a.all.R0, t_parameters'size/8, current_id, current_a.all.mode)
      then
         svc_params_a := to_parameters_access (frame_a.all.R0);
      else
         if svc /= SVC_EXIT         and
            svc /= SVC_YIELD        and
            svc /= SVC_RESET        and
            svc /= SVC_INIT_DONE    and
            svc /= SVC_LOCK_ENTER   and
            svc /= SVC_LOCK_EXIT    and
            svc /= SVC_PANIC
         then
            -- R0 points outside the caller's data area
            pragma DEBUG (debug.log (debug.ERROR,
               current_a.all.name & "svc_handler(): invalid @parameters: " &
               unsigned_32'image (frame_a.all.R0)));
            ewok.tasks.set_state
              (current_id, TASK_MODE_MAINTHREAD, TASK_STATE_RUNNABLE);
            set_return_value
              (current_id, current_a.all.mode, SYS_E_DENIED);
            return frame_a;
         end if;
      end if;

      -------------------
      -- Managing SVCs --
      -------------------

      case svc is

         when SVC_EXIT           =>
            ewok.syscalls.exiting.svc_exit (current_id, current_a.all.mode);
            return ewok.sched.do_schedule (frame_a);

         when SVC_YIELD          =>
            ewok.syscalls.yield.svc_yield (current_id, current_a.all.mode);
            return frame_a;

         when SVC_GET_TIME       =>
            ewok.syscalls.gettick.svc_gettick
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_RESET          =>
            ewok.syscalls.reset.svc_reset (current_id, current_a.all.mode);
            return frame_a;

         when SVC_SLEEP          =>
            ewok.syscalls.sleep.svc_sleep
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_GET_RANDOM     =>
            ewok.syscalls.rng.svc_get_random
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_LOG            =>

            ewok.syscalls.log.svc_log
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_REGISTER_DEVICE   =>
            ewok.syscalls.init.svc_register_device
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_REGISTER_DMA      =>
#if CONFIG_KERNEL_DMA_ENABLE
            ewok.syscalls.dma.svc_register_dma
              (current_id, svc_params_a.all, current_a.all.mode);
#else
            set_return_value (current_id, current_a.all.mode, SYS_E_DENIED);
#end if;
            return frame_a;

         when SVC_REGISTER_DMA_SHM  =>
#if CONFIG_KERNEL_DMA_ENABLE
            ewok.syscalls.dma.svc_register_dma_shm
              (current_id, svc_params_a.all, current_a.all.mode);
#else
            set_return_value (current_id, current_a.all.mode, SYS_E_DENIED);
#end if;
            return frame_a;

         when SVC_GET_TASKID =>
            ewok.syscalls.init.svc_get_taskid
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_INIT_DONE      =>
            ewok.syscalls.init.svc_init_done (current_id, current_a.all.mode);
            return frame_a;

         when SVC_IPC_RECV_SYNC  =>
            ewok.syscalls.ipc.svc_ipc_do_recv
              (current_id, svc_params_a.all, true, current_a.all.mode);
            return ewok.sched.do_schedule (frame_a);

         when SVC_IPC_SEND_SYNC  =>
            ewok.syscalls.ipc.svc_ipc_do_send
              (current_id, svc_params_a.all, true, current_a.all.mode);
            return ewok.sched.do_schedule (frame_a);

         when SVC_IPC_RECV_ASYNC =>
            ewok.syscalls.ipc.svc_ipc_do_recv
              (current_id, svc_params_a.all, false, current_a.all.mode);
            return ewok.sched.do_schedule (frame_a);

         when SVC_IPC_SEND_ASYNC =>
            ewok.syscalls.ipc.svc_ipc_do_send
              (current_id, svc_params_a.all, false, current_a.all.mode);
            return ewok.sched.do_schedule (frame_a);

         when SVC_GPIO_SET       =>
            ewok.syscalls.cfg.gpio.svc_gpio_set (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_GPIO_GET       =>
            ewok.syscalls.cfg.gpio.svc_gpio_get (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_GPIO_UNLOCK_EXTI =>
            ewok.syscalls.cfg.gpio.svc_gpio_unlock_exti
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_DMA_RECONF  =>
#if CONFIG_KERNEL_DMA_ENABLE
            ewok.syscalls.dma.svc_dma_reconf
              (current_id, svc_params_a.all, current_a.all.mode);
#else
            set_return_value (current_id, current_a.all.mode, SYS_E_DENIED);
#end if;
            return frame_a;

         when SVC_DMA_RELOAD  =>
#if CONFIG_KERNEL_DMA_ENABLE
            ewok.syscalls.dma.svc_dma_reload
              (current_id, svc_params_a.all, current_a.all.mode);
#else
            set_return_value (current_id, current_a.all.mode, SYS_E_DENIED);
#end if;
            return frame_a;

         when SVC_DMA_DISABLE =>
#if CONFIG_KERNEL_DMA_ENABLE
            ewok.syscalls.dma.svc_dma_disable
              (current_id, svc_params_a.all, current_a.all.mode);
#else
            set_return_value (current_id, current_a.all.mode, SYS_E_DENIED);
#end if;
            return frame_a;

         when SVC_DEV_MAP     =>
            ewok.syscalls.cfg.dev.svc_dev_map
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_DEV_UNMAP   =>
            ewok.syscalls.cfg.dev.svc_dev_unmap
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_DEV_RELEASE =>
            ewok.syscalls.cfg.dev.svc_dev_release
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

         when SVC_LOCK_ENTER  =>
            ewok.syscalls.lock.svc_lock_enter (current_id, current_a.all.mode);
            return frame_a;

         when SVC_LOCK_EXIT   =>
            ewok.syscalls.lock.svc_lock_exit (current_id, current_a.all.mode);
            return frame_a;

         when SVC_PANIC       =>
            ewok.syscalls.exiting.svc_panic (current_id);
            return ewok.sched.do_schedule (frame_a);

         when SVC_ALARM       =>
            ewok.syscalls.alarm.svc_alarm
              (current_id, svc_params_a.all, current_a.all.mode);
            return frame_a;

      end case;

   end svc_handler;


end ewok.syscalls.handler;
