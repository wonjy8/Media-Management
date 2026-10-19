begin;
insert into auth.users(id) values('80000000-0000-0000-0000-000000000001');
insert into admins values('80000000-0000-0000-0000-000000000001');
insert into equipment(id,code,name,quantity) values('80000000-0000-0000-0000-000000000002','PDF-001','서식 테스트 장비',5);
create temporary table template_test_state(old_loan jsonb,old_template jsonb,new_template jsonb);
do $$declare a jsonb;t jsonb;args jsonb;begin
 t:=current_pdf_template();
 if not validate_pdf_template(t) then raise exception 'default template is invalid';end if;
 foreach args in array array[t-'title',jsonb_set(t,'{showLogo}','null'),jsonb_set(t,'{fontSize}','100'),jsonb_set(t,'{columns}','[]'),jsonb_set(t,'{logoUrl}','"javascript:alert(1)"')] loop
  if validate_pdf_template(args) then raise exception 'invalid template accepted';end if;
 end loop;
 a:=equipment_workflow('create','{"name":"테스트","phone":"01012345678","department":"청년부","position":"팀장","reason":"서식 테스트","start":"2032-01-01","end":"2032-01-02","items":{"80000000-0000-0000-0000-000000000002":1},"pdfTemplate":{"title":"forged"}}');
 if a->'pdfTemplate'<>t then raise exception 'snapshot missing or client forged template';end if;
 insert into template_test_state values(a,t,null);
end $$;
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000099',true);
set local role authenticated;
do $$begin
 begin perform save_pdf_template(current_pdf_template(),(current_pdf_template()->>'version')::bigint);raise exception 'non-admin saved';exception when insufficient_privilege then null;end;
end $$;
reset role;
grant select,update,delete on pdf_templates,pdf_template_current to authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$declare t jsonb;n jsonb;affected integer;begin
 update pdf_templates set settings='{}';get diagnostics affected=row_count;if affected<>0 then raise exception 'direct admin mutation allowed';end if;
 delete from pdf_template_current;get diagnostics affected=row_count;if affected<>0 then raise exception 'direct pointer deletion allowed';end if;
 t:=current_pdf_template();
 n:=save_pdf_template(jsonb_set(t,'{title}','"변경된 서식 제목"'),(t->>'version')::bigint);
 if n->>'title'<>'변경된 서식 제목' or (n->>'version')::bigint<=(t->>'version')::bigint then raise exception 'save did not return new version';end if;
 begin perform save_pdf_template(t,(t->>'version')::bigint);raise exception 'stale save accepted';exception when others then if sqlerrm not like '%CONFLICT%' then raise;end if;end;
 begin perform save_pdf_template(t-'title',(n->>'version')::bigint);raise exception 'invalid template saved';exception when others then if sqlerrm not like '%INVALID_TEMPLATE%' then raise;end if;end;
end $$;
reset role;
do $$declare a jsonb;b jsonb;t jsonb;begin
 select old_loan,old_template into a,t from template_test_state;
 if loan_json((a->>'databaseId')::uuid)->'pdfTemplate'<>t then raise exception 'old application template changed';end if;
 a:=equipment_workflow('update',jsonb_build_object('id',a->>'id','revision',1,'name','테스트','phone','01012345678','department','청년부','position','팀장','reason','수정 테스트','start','2032-01-01','end','2032-01-02','items',a->'items'));
 if a->'pdfTemplate'<>t then raise exception 'editing rewrote template';end if;
 b:=equipment_workflow('create','{"name":"새신청","phone":"01012345678","department":"청년부","position":"팀장","reason":"새 서식","start":"2032-01-03","end":"2032-01-04","items":{"80000000-0000-0000-0000-000000000002":1}}');
 if b->'pdfTemplate'->>'title'<>'변경된 서식 제목' then raise exception 'new application did not use saved template';end if;
 if not exists(select 1 from audit_log where action='pdf_template_saved') then raise exception 'missing audit';end if;
 if has_function_privilege('anon','save_pdf_template(jsonb,bigint)','EXECUTE') then raise exception 'anon can save';end if;
 update loans set pdf_template=null where id=(a->>'databaseId')::uuid;
 if loan_json((a->>'databaseId')::uuid)->'pdfTemplate'<>'null'::jsonb then raise exception 'legacy template not retained';end if;
end $$;
rollback;
