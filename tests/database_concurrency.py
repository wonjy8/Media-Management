"""Run against the disposable media-postgres-test Docker container after migrations."""
import subprocess
import time

def sql(query, check=True):
    return subprocess.run(['docker','exec','media-postgres-test','psql','-U','postgres','-At','-v','ON_ERROR_STOP=1','-c',query],capture_output=True,text=True,check=check)

item='20000000-0000-0000-0000-000000000001'
sql(f"insert into equipment(id,code,name,quantity) values('{item}','CONCURRENT','동시 신청 테스트',1)")
query="select equipment_workflow('create','{\"name\":\"테스트\",\"phone\":\"01000000000\",\"reason\":\"동시성\",\"start\":\"2027-03-01\",\"end\":\"2027-03-02\",\"items\":{\""+item+"\":1}}');"
first=subprocess.Popen(['docker','exec','media-postgres-test','psql','-U','postgres','-At','-v','ON_ERROR_STOP=1','-c',"set application_name='media_first'; begin; "+query+'select pg_sleep(3); commit;'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
try:
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        if sql("select count(*) from pg_stat_activity where application_name='media_first' and wait_event='PgSleep'").stdout.strip()=='1':
            break
        time.sleep(.05)
    else:
        raise AssertionError('first transaction did not enter holding period')
    second=sql(query,check=False)
    out,err=first.communicate(timeout=15)
    assert first.returncode==0,err
    assert second.returncode!=0 and 'INSUFFICIENT_STOCK' in second.stderr,second
    assert sql(f"select sum(quantity) from loan_items where equipment_id='{item}'").stdout.strip()=='1'
    print('PASS: first transaction wins; competing request is rejected without overselling')
finally:
    if first.poll() is None: first.terminate();first.wait()
    sql(f"delete from audit_log where loan_id in(select loan_id from loan_items where equipment_id='{item}'); delete from loan_items where equipment_id='{item}'; delete from loans where reason='동시성'; delete from equipment where id='{item}';")
