package main

import (
	"net/http"
	"strconv"
	"sync"
	"sync/atomic"

	"github.com/gin-gonic/gin"
)

type Pet struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type store struct {
	mu   sync.RWMutex
	pets map[int]Pet
	next atomic.Int64
}

func newStore() *store {
	s := &store{pets: make(map[int]Pet)}
	s.next.Store(1)
	return s
}

func (s *store) list() []Pet {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Pet, 0, len(s.pets))
	for _, p := range s.pets {
		out = append(out, p)
	}
	return out
}

func (s *store) create(name string) Pet {
	id := int(s.next.Add(1)) - 1
	p := Pet{ID: id, Name: name}
	s.mu.Lock()
	s.pets[id] = p
	s.mu.Unlock()
	return p
}

func (s *store) get(id int) (Pet, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.pets[id]
	return p, ok
}

func main() {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	s := newStore()

	s.create("initial-pet")

	r.GET("/pets", func(c *gin.Context) {
		c.JSON(http.StatusOK, s.list())
	})

	r.POST("/pets", func(c *gin.Context) {
		var body struct {
			Name string `json:"name" binding:"required"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusCreated, s.create(body.Name))
	})

	r.GET("/pets/:id", func(c *gin.Context) {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
			return
		}
		p, ok := s.get(id)
		if !ok {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.JSON(http.StatusOK, p)
	})

	r.Run(":8081")
}
