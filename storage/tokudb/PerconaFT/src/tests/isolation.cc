/* -*- mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*- */
// vim: ft=cpp:expandtab:ts=8:sw=4:softtabstop=4:
#ident "$Id$"
/*======
This file is part of PerconaFT.


Copyright (c) 2006, 2015, Percona and/or its affiliates. All rights reserved.

    PerconaFT is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, version 2,
    as published by the Free Software Foundation.

    PerconaFT is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with PerconaFT.  If not, see <http://www.gnu.org/licenses/>.

----------------------------------------

    PerconaFT is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License, version 3,
    as published by the Free Software Foundation.

    PerconaFT is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with PerconaFT.  If not, see <http://www.gnu.org/licenses/>.
======= */

#ident "Copyright (c) 2006, 2015, Percona and/or its affiliates. All rights reserved."

// Test that isolation works right for subtransactions.
// In particular, check to see what happens if a subtransaction has different isolation level from its parent.

#include "test.h"

const int envflags = DB_INIT_MPOOL|DB_CREATE|DB_THREAD |DB_INIT_LOCK|DB_INIT_LOG|DB_INIT_TXN|DB_PRIVATE;

int test_main (int argc, char * const argv[]) {
    parse_args(argc, argv);
    int r;
    toku_os_recursive_delete(TOKU_TEST_FILENAME);
    toku_os_mkdir(TOKU_TEST_FILENAME, S_IRWXU+S_IRWXG+S_IRWXO);
    DB_ENV *env;
    r = db_env_create(&env, 0);                                                         CKERR(r);
    env->set_errfile(env, stderr);
    r = env->open(env, TOKU_TEST_FILENAME, envflags, S_IRWXU+S_IRWXG+S_IRWXO);                      CKERR(r);
    
    DB *db;
    {
	DB_TXN *txna;
	r = env->txn_begin(env, NULL, &txna, 0);                                        CKERR(r);

	r = db_create(&db, env, 0);                                                     CKERR(r);
	r = db->open(db, txna, "foo.db", NULL, DB_BTREE, DB_CREATE, 0666);              CKERR(r);

	DBT key,val;
	r = db->put(db, txna, dbt_init(&key, "a", 2), dbt_init(&val, "a", 2), 0);       CKERR(r);

	r = txna->commit(txna, 0);                                                      CKERR(r);
    }
    DB_TXN *txna, *txnx;
    r = env->txn_begin(env, NULL, &txna, DB_READ_UNCOMMITTED);                          CKERR(r);
    r = env->txn_begin(env, NULL, &txnx, 0);                                            CKERR(r);

    // X writes a value, and B tries to read it in uncommitted
    {
//	DB_TXN *txnb;
//	r = env->txn_begin(env, txna, &txnb, DB_READ_UNCOMMITTED);                      CKERR(r);
	{
	    DBT key,val;
	    r = db->put(db, txnx, dbt_init(&key, "x", 2), dbt_init(&val, "x", 2), 0);   CKERR(r);
	    dbt_init_malloc(&val);
	    r = db->get(db, txna, dbt_init(&key, "x", 2), &val, 0);                     CKERR(r);
            toku_free(val.data);
            val.data = NULL;
	}
//	r = txnb->commit(txnb, 0);                                                      CKERR(r);
    }
    r = txna->commit(txna, 0);                                                          CKERR(r);
    r = txnx->commit(txnx, 0);                                                          CKERR(r);

    r = db->close(db, 0);                                                               CKERR(r);
    r = env->close(env, 0);                                                             CKERR(r);
    
    return 0;
}
