-- Run on disposable Postgres after migrations; test identities contain no real data.
begin;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000001');
insert into admins values('00000000-0000-0000-0000-000000000001');
insert into equipment(id,code,name,quantity) values('10000000-0000-0000-0000-000000000001','TEST-001','테스트 케이블',2);
do $$
declare a jsonb; b jsonb; c jsonb; id text; blocked boolean:=false; i integer;
begin
 a:=equipment_workflow('create','{"name":"테스트","phone":"01000000000","reason":"검증","start":"2027-01-01","end":"2027-01-03","items":{"10000000-0000-0000-0000-000000000001":2}}');
 id:=a->>'id';
 if id !~ '^반출-[0-9]{4}-[0-9]{2}-[0-9]{3,}$' then raise exception 'unexpected number: %',id; end if;
 begin
 perform equipment_workflow('create','{"name":"다른이","phone":"01000000001","reason":"충돌","start":"2027-01-03","end":"2027-01-04","items":{"10000000-0000-0000-0000-000000000001":1}}');
 exception when others then if sqlerrm like '%INSUFFICIENT_STOCK%' then blocked:=true; else raise; end if; end;
 if not blocked then raise exception 'overlap was not blocked'; end if;
 -- Authorization and exact identity matching.
 blocked:=false;
 begin perform equipment_workflow('cancel',jsonb_build_object('id',id,'name','다른이','phone','01000000000','revision',1));
 exception when others then if sqlerrm like '%NOT_FOUND%' then blocked:=true; else raise; end if; end;
 if not blocked then raise exception 'identity bypass'; end if;
 -- Checkout is allowed before approval.
 a:=equipment_workflow('checkout',jsonb_build_object('id',id,'revision',1),'00000000-0000-0000-0000-000000000001');
 if not (a->>'out')::boolean or (a->>'approved')::boolean then raise exception 'checkout approval coupling'; end if;
 a:=equipment_workflow('return',jsonb_build_object('id',id,'name','테스트','phone','01000000000','revision',2,'items',jsonb_build_object('10000000-0000-0000-0000-000000000001',1)));
 if (a->'returned'->>'10000000-0000-0000-0000-000000000001')::integer<>1 then raise exception 'partial return failure'; end if;
 -- Optimistic revision prevents replaying the same return.
 blocked:=false;
 begin perform equipment_workflow('return',jsonb_build_object('id',id,'name','테스트','phone','01000000000','revision',2,'items',jsonb_build_object('10000000-0000-0000-0000-000000000001',1)));
 exception when others then if sqlerrm like '%CONFLICT%' then blocked:=true; else raise; end if; end;
 if not blocked then raise exception 'return replay'; end if;
 a:=equipment_workflow('approve',jsonb_build_object('id',id,'revision',3),'00000000-0000-0000-0000-000000000001');
 if not (a->>'approved')::boolean then raise exception 'late approval failure'; end if;
 a:=equipment_workflow('undo_return',jsonb_build_object('id',id,'revision',4,'reason','오입력 정정'),'00000000-0000-0000-0000-000000000001');
 if (a->'returned'->>'10000000-0000-0000-0000-000000000001')::integer<>0 then raise exception 'undo failure'; end if;
 b:=equipment_workflow('create','{"name":"테스트","phone":"01000000000","reason":"수정 검증","start":"2027-02-01","end":"2027-02-03","items":{"10000000-0000-0000-0000-000000000001":1}}');
 b:=equipment_workflow('update',jsonb_build_object('id',b->>'id','name','테스트','phone','01000000000','revision',1,'start','2027-02-02','end','2027-02-04','reason','변경','items',jsonb_build_object('10000000-0000-0000-0000-000000000001',2)));
 if (b->>'approved')::boolean then raise exception 'update must reset approval'; end if;
 for i in 1..40 loop if not consume_request_limit('test-ip','test-target','lookup') then raise exception 'premature limit'; end if; end loop;
 if consume_request_limit('test-ip','test-target','lookup') then raise exception 'rate limit failure'; end if;
 update loans set created_at=now()-interval '1 year 1 day';
 perform anonymize_expired_loans();
 if exists(select 1 from loans where borrower_name is not null or borrower_phone is not null) then raise exception 'anonymization failure'; end if;
 if has_function_privilege('anon','public.equipment_workflow(text,jsonb,uuid)','execute') then raise exception 'public workflow execution'; end if;
 raise notice 'PASS: numbering, date overlap, identity, checkout, partial return, replay, late approval, undo, reapproval, rate limit, anonymization, RPC privilege';
end $$;
rollback;
