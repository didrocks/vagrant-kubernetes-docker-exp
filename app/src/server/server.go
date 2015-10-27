package main

import (
	"bytes"
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"os"

	_ "github.com/go-sql-driver/mysql"
)

var hostname string
var db *sql.DB

func incrementvisit(w http.ResponseWriter, r *http.Request) {
	var response bytes.Buffer
	response.WriteString(fmt.Sprintf("Hello from %s!\n\nYou visited:\n", hostname))

	tx, err := db.Begin()
	checkConnectDb(err, w)

	_, err = tx.Exec(fmt.Sprintf("INSERT INTO visitstracker (visits, containername) VALUES (1, '%s') "+
		"ON DUPLICATE KEY UPDATE visits = visits + 1", hostname))
	checkConnectDb(err, w)

	rows, err := tx.Query("SELECT * FROM visitstracker")
	checkConnectDb(err, w)

	for rows.Next() {
		var visits int
		var containername string
		err = rows.Scan(&visits, &containername)
		checkConnectDb(err, w)
		response.WriteString(fmt.Sprintf("- %s %d times\n", containername, visits))
	}

	err = tx.Commit()
	checkConnectDb(err, w)
	io.WriteString(w, response.String())
}

/* helper printing we couldn't connect to DB */
func checkConnectDb(err error, w http.ResponseWriter) {
	if err == nil {
		return
	}
	checkErr(err)
}

/* panic if we can't connect to DB, another container will respawn with optinal new db parameters */
func checkErr(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	// get hostname for this container
	var err error
	hostname, err = os.Hostname()
	checkErr(err)

	// open database
	db, err = sql.Open("mysql", fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8&timeout=30s",
		os.Getenv("MYSQL_USER"), os.Getenv("MYSQL_PASSWORD"),
		os.Getenv("DB_SERVICE_SERVICE_HOST"), os.Getenv("DB_SERVICE_SERVICE_PORT"), os.Getenv("MYSQL_DATABASE")))
	checkErr(err)
	defer db.Close()

	// try to create the table if another pod hasn't done it
	_, err = db.Exec("CREATE TABLE IF NOT EXISTS `visitstracker` " +
		"(`visits` INT(10) NOT NULL DEFAULT 0, `containername` VARCHAR(64) UNIQUE, PRIMARY KEY (`containername`));")
	checkErr(err)

	// serve on port 80
	http.HandleFunc("/", incrementvisit)
	http.ListenAndServe(":80", nil)
}
