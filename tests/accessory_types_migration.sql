-- Run in a local/test database after 011; all fixture changes roll back.
begin;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select true$$;
do $$declare parent_id uuid;other_id uuid;child_id uuid;
begin
 parent_id:=admin_save_equipment_with_accessories('{"name":"분류 테스트 본체A","code":"TYPE-A","quantity":2,"repair_quantity":0,"active":true,"is_accessory":false}','[]');
 other_id:=admin_save_equipment_with_accessories('{"name":"분류 테스트 본체B","code":"TYPE-B","quantity":2,"repair_quantity":0,"active":true,"is_accessory":false}','[]');
 child_id:=admin_save_equipment_with_accessories('{"name":"분류 테스트 부속품","code":null,"quantity":2,"repair_quantity":0,"active":true,"is_accessory":true}','[]',null,
  jsonb_build_array(jsonb_build_object('id',parent_id,'quantity',1,'selectedByDefault',true),jsonb_build_object('id',other_id,'quantity',1,'selectedByDefault',true)));
 begin
  perform admin_save_equipment_with_accessories('{"name":"이전 화면의 수정","code":null,"quantity":2,"repair_quantity":0,"active":true}','[]',child_id);
  raise exception 'omitted flag cleared accessory classification';
 exception when check_violation then null;end;
 if (select count(*) from equipment_accessories where accessory_id=child_id)<>2 then raise exception 'shared parents lost';end if;
 begin
  perform admin_save_equipment_with_accessories('{"name":"잘못된 분류","code":null,"quantity":1,"repair_quantity":0,"active":true,"is_accessory":true}','[]');
  raise exception 'orphan accessory accepted';
 exception when check_violation then null;end;
 begin
  perform admin_save_equipment_with_accessories('{"name":"잘못된 중첩","code":null,"quantity":1,"repair_quantity":0,"active":true,"is_accessory":true}','[]',null,
   jsonb_build_array(jsonb_build_object('id',child_id,'quantity',1,'selectedByDefault',true)));
  raise exception 'nested accessory accepted';
 exception when check_violation then null;end;
end $$;
set constraints all immediate;
set constraints all deferred;
select admin_save_equipment_with_accessories('{"name":"일반 장비로 전환","code":null,"quantity":2,"repair_quantity":0,"active":true,"is_accessory":false}','[]',(select id from equipment where name='분류 테스트 부속품'),'[]');
set constraints all immediate;
do $$begin
 if exists(select 1 from equipment_accessories where accessory_id=(select id from equipment where name='일반 장비로 전환')) then raise exception 'stale parent links remain';end if;
end $$;
rollback;
