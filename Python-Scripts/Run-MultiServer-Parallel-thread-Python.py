from threading import Thread, Lock

class DatabaseWorker(Thread):
    __lock = Lock()

    def __init__(self, db, query, result_queue):
        Thread.__init__(self)
        self.db = db
        self.query = query
        self.result_queue = result_queue

    def run(self):
        result = None
        logging.info("Connecting to database...")
        try:
            conn = connect(host=host, port=port, database=self.db)
            curs = conn.cursor()
            curs.execute(self.query)
            result = curs
            curs.close()
            conn.close()
        except Exception as e:
            logging.error("Unable to access database %s" % str(e))
        self.result_queue.append(result)

delay = 1
result_queue = []
worker1 = DatabaseWorker("db1", "select something from sometable",
        result_queue)
worker2 = DatabaseWorker("db1", "select something from othertable",
        result_queue)
worker1.start()
worker2.start()

# Wait for the job to be done
while len(result_queue) < 2:
    sleep(delay)
job_done = True
worker1.join()
worker2.join()