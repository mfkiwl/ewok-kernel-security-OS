------------------------------------------------------------------------
----      Copyright (c) 15-01-2018, ANSSI
----      All rights reserved.
----
---- This file is autogenerated by tools/gen_ld.pl
----
---- This file describes the applications layout and permissions for
---- the current build.
---- Please see the above script for details.
----
--------------------------------------------------------------------------

--
-- This file is autogenerated ! Don't try to update it as it is
-- regenerated each time the kernel is built !
--

with interfaces;        use interfaces;
with types;             use types;
with ewok.tasks_shared; use ewok.tasks_shared;
with ewok.tasks;	    use ewok.tasks;


package config.applications is

   -- We define a memory offset as an unsigned value up to 4Mb. On a
   -- microkernel system, this should be enough for nearly all needs.
   -- FIXME: this type can be added to the types.ads package after the
   -- end of the newmem tests
   subtype t_memory_offset is unsigned_32 range 0 .. 4194304;

   -- An application section can be up to 512K length
   subtype t_application_section_size is unsigned_32 range 0 .. 524288;

   -- An application data section (mapped in RAM) can be up to 65K length
   subtype t_application_data_size is unsigned_16 range 0 .. 65535;

   type t_application is record
      -- Task name
      name              : ewok.tasks.t_task_name;
      -- Text section addr in flash
      text_offset       : t_memory_offset;
      -- Text size, in bytes
      text_size         : t_application_section_size;
      -- GOT section addr in flash
      got_offset        : t_memory_offset;
      -- GOT size, in bytes
      got_size          : t_application_section_size;
      -- Data address in RAM
      data_offset       : t_memory_offset;
      -- Data section offset in flash
      data_flash_offset : t_memory_offset;
      -- Data size
      data_size         : t_application_data_size;
      -- BSS size
      bss_size          : t_application_data_size;
      -- Heap size
      heap_size         : t_application_data_size;
      -- Requested stack size
      stack_size        : t_application_data_size;
      -- Entrypoint offset, starting at application text start addr
      entrypoint_offset : t_memory_offset;
      -- Isr_entrypoint offset, starting at  application text start addr
      isr_entrypoint_offset : t_memory_offset;
      -- Security domain
      domain            : unsigned_8;
      -- Priority
      priority          : unsigned_8;
   end record;

   -- List of activated applications
   subtype t_real_task_id is t_task_id
