select fg.name,mf.name,mf.physical_name 
from sys.filegroups fg join sys.master_files mf on mf.data_space_id=fg.data_space_id
where database_id=db_ID()
