package replicatedlog

import shapeless._
import shapeless.Zipper._
import UnaryTCConstraint._
import scala.collection.immutable.Queue
import scalaz.{ Zipper => _, _ }
import scalaz.effect._
import scalaz.syntax.applicative._
import scalaz.syntax.monad._
import scalaz.syntax.traverse._
import scalaz.Free._
import scalaz.Trampoline._
import scalaz.std.list._
import scala.tools.jline.console.ConsoleReader
import atto._
import Atto._
import IO._

object ReplicatedLog extends SafeApp {
  override def run(args: ImmutableArray[String]) = for {
    messages <- newIORef(Map.empty[Int, Message])
    console <- Console.withPrompt("> ")
    nodes <- freshNodes
    _ <- foreverIO(loop(messages, nodes, console))
  } yield ()
  
  type KVStore = Map[String, Option[Int]]

  val freshNodes: IO[Vector[Node]] = for {
    n1 <- node(0)
    n2 <- node(1)
    n3 <- node(2)
  } yield Vector(n1, n2, n3)

  def loop(messages: IORef[Map[Int, Message]], nodes: Vector[Node], console: Console): IO[Unit] = for {
    line <- console.readLine
    cmd <- IO(command.parse(line).either match {
      case -\/(_) => Fail("invalid commmand")
      case \/-(cmd) => cmd
    })
    result <- interpret(messages, nodes, cmd)
    _ <- putStrLn(result)
  } yield ()
  
  def interpret(messages: IORef[Map[Int, Message]], nodes: Vector[Node], c: Command): IO[String] = c match {
    case Increment(nodeN, key) =>
      nodes(nodeN).increment(key).map(_.get.toString)
    case Decrement(nodeN, key) =>
      nodes(nodeN).decrement(key).map(_.get.toString)
    case GetValue(nodeN, key) =>
      nodes(nodeN).get(key).map(x => x match { case None => "null"; case Some(x) => x.toString })
    case SendLog(from, to) =>
      nodes(from).send(to).flatMap(queueMsg(messages, _)).map(_.toString)
    case ReceiveLog(tn) =>
      for {
        m <- messages.read.map(ms => ms(tn))
        r <- nodes(m.receiver).receive(m)
      } yield r.toString
    case PrintState(n) =>
      nodes(n).printState
    case Fail(e) =>
      IO(e)
  }

  def queueMsg(map: IORef[Map[Int, Message]], m: Message): IO[Int] = for {
    mp <- map.read
    max <- IO(mp.keys.toVector.sorted.reverse.headOption.getOrElse(0))
    _ <- map.mod(mp => mp + ((max + 1) -> m))
  } yield max + 1

  def run(c: Command) = c.toString

  def foreverIO[A, B >: Nothing](m: IO[A]): IO[B] = m >>= (_ => foreverIO(m))

  def params[H <: HList : *->*[Parser]#λ, OT](ps: H)(implicit reducer: shapeless.ops.hlist.RightReducer[H, seqHParsers.type]) = 
    ps.reduceRight(seqHParsers)

  def args[H <: HList: *->*[Parser]#λ, RT](l: H)(implicit reducer: shapeless.ops.hlist.RightReducer.Aux[H, seqHParsers.type, Parser[RT]]) =
    parens(l.reduceRight(seqHParsers))

  object seqHParsers extends Poly2 {
    implicit def caseParserList[H, L <: HList] = 
      at[Parser[H], Parser[L]] { (p, ps) => 
        for {
          x  <- p
          xs <- ps
        } yield x :: xs
      }

    implicit def caseParserSingle[H, L] = 
      at[Parser[H], Parser[L]] { (p1, p2) => 
        for {
          x  <- p1
          y  <- p2
        } yield x :: y :: HNil
      }
  }
  
  def sequenceP[H <: HList, K[_]](l: H)(implicit seq: Sequencer[H, K], tc: UnaryTCConstraint[H, K], m: Monad[K]): seq.Out = seq(l)

  trait Sequencer[L <: HList, K[_]] extends DepFn1[L]

  object Sequencer {
    def apply[L <: HList, K[_]: Applicative](implicit sequencer: Sequencer[L, K]): Aux[L, K, sequencer.Out] = sequencer

    type Aux[L <: HList, K0[_], Out0] = Sequencer[L, K0] { type Out = Out0 }
    
   /* implicit def hnilSequencer[K[_]]: Aux[HNil, K[_], HNil] = 
      new Sequencer[HNil, K] {
        type Out = HNil
      }
    } */
        
    implicit def hsingleSequencer[H, K[_]: Applicative]: Aux[K[H] :: HNil, K, K[H :: HNil]] =
      new Sequencer[K[H] :: HNil, K] {
        type Out = K[H :: HNil]
        def apply(l: K[H] :: HNil): Out = Applicative[K].apply(l.head)(_ :: HNil)
      }
    
    implicit def hlistSequencer[H, T <: HList, K[_]: Applicative, OutT <: HList]
      (implicit s: Sequencer.Aux[T, K, K[OutT]]): Aux[K[H] :: T, K, K[H :: OutT]] =
      new Sequencer[K[H] :: T, K] {
        type Out = K[H :: OutT]
        def apply(l : K[H] :: T): Out = 
          Applicative[K].apply2(l.head, s(l.tail))(_ :: _)
      } 
  }

  def command: Parser[Command] = (
    string("Increment")  ~> args((int <~ argComma) :: qstring :: HNil).map(p => Increment(p(0) - 1, p(1)))
  | string("Decrement")  ~> args((int <~ argComma) :: qstring :: HNil).map(p => Decrement(p(0) - 1, p(1)))
  | string("getValue")   ~> args((int <~ argComma) :: qstring :: HNil).map(p => GetValue(p(0) - 1, p(1))) 
  | string("PrintState") ~> args(int :: opt(string("")) :: HNil).map(p => PrintState(p(0) - 1))
  | string("SendLog")    ~> args((int <~ argComma) :: int :: HNil).map(p => SendLog(p(0) - 1, p(1) - 1))
  | string("ReceiveLog") ~> args(int :: opt(string("")) :: HNil).map(p => ReceiveLog(p(0)))
  )
  
  sealed trait Command
  case class Increment(node: Int, key: String) extends Command
  case class Decrement(node: Int, key: String) extends Command
  case class GetValue(node: Int, key: String) extends Command
  case class PrintState(node: Int) extends Command
  case class SendLog(to: Int, from: Int) extends Command
  case class ReceiveLog(tn: Int) extends Command
  case class Fail(e: String) extends Command

  def quotes[A](p: Parser[A]): Parser[A] = 
    (char('"') ~> p) <~ char('"')

  def qstring = quotes(many(letter).map(_.mkString("")))

  def argComma = many(spaceChar) >>= (_ => char(',')) >>= (_ => many(spaceChar))

  def parens[A](p: Parser[A]): Parser[A] = 
    (char('(') ~> p) <~ char(')')

  type TTable = Vector[Vector[Int]]
  
  trait LogOp
  case class Inc(name: String) extends LogOp {
    override def toString = s"increment($name)"
  }

  case class Dec(name: String) extends LogOp {
    override def toString = s"decrement($name)"
  }

  case class LogEntry(operation: LogOp, node: Int, time: Int) {
    override def toString = operation.toString
  }
  case class Message(sender: Int, receiver: Int, log: Queue[LogEntry], ttable: TTable)

  case class Node private[ReplicatedLog] (
     label: Int, 
     log: IORef[Queue[LogEntry]], 
     store: IORef[Map[String, Option[Int]]],
     table: IORef[TTable]
    )
  {
    def hasRec(table: TTable, e: LogEntry, k: Int): Boolean = {
      table(k)(e.node) >= e.time
    }

    def get(k: String): IO[Option[Int]] = store.read.map(_(k))

    def increment(k: String): IO[Option[Int]] = for {
      v <- store.mod { s => 
        val v = s(k).getOrElse(0)
        s + ((k, Some(v + 1)))
      }
      t <- table.mod { t => 
          val row = t(label)
          val v = row(label)
          t updated (label, row updated (label, v + 1))
      }
      _ <- log.mod(l => l.enqueue(LogEntry(Inc(k), label, t(label)(label))))
    } yield v(k)

    def decrement(k: String): IO[Option[Int]] = for {
      v <- store.mod { s => 
        val v = s(k).getOrElse(0)
        s + ((k, Some(v - 1)))
      }
      t <- table.mod { t => 
          val row = t(label)
          val v = row(label)
          t updated (label, row updated (label, v + 1))
      }
      _ <- log.mod(l => l.enqueue(LogEntry(Dec(k), label, t(label)(label))))
    } yield v(k)


    def printState: IO[String] = for {
      t <- table.read
      l <- log.read
    } yield s"Log: ${l.mkString("{\n", "\n", "\n}\n")}" + s"TimeTable:\n${printTable(t).mkString("\n")}"
  
    def printTable(v: Vector[Vector[Int]]) = for {
      i <- v
    } yield s"| ${i(0)}    ${i(1)}    ${i(2)} |"

    def send(to: Int): IO[Message] = for {
        t <- table.read
        l <- log.read
      } yield {
        val slog = l.filter(!hasRec(t, _, to))
        Message(label, to, slog, t)
      }

    def receive(m: Message): IO[Unit] = m match {
      case Message(sender, _, nlog, ttable) =>
        val currentTime = ttable(label)(label)
       
        val updateLog = log.mod(l => l ++ nlog)

        val updateS = nlog.toList.map { x => x match {
          case LogEntry(Inc(key), _, _) => store.mod(m => m + ((key, Some((m(key).getOrElse(0) + 1)))))
          case LogEntry(Dec(key), _, _) => store.mod(m => m + ((key, Some((m(key).getOrElse(0) - 1)))))
        }}

        val updateT = table.mod { tb => 
          val iT = for {
            (r1, r2) <- tb.zip(ttable)
          } yield for {
            (i, j) <- r1.zip(r2)
          } yield if (j > i) j else i

          val updatedR = iT(label).zip(iT(sender)).map { case (i, j) => if (j > i) j else i }
          iT updated (label, updatedR)
        }

        val garbageCollect = for {
          t <- table.read
          _ <- log.mod { l =>
            l.filter(le => !(0 to 2).map(hasRec(t, le, _)).reduce(_ && _))
          }
        } yield ()
        updateLog >>= (_ => updateS.sequence) >>= (_ => updateT) >>= (_ => garbageCollect)
    }
  }

  def node(label: Int): IO[Node] = for {
    lref <- newIORef(Queue.empty[LogEntry])
    sref <- newIORef(Map.empty[String, Option[Int]].withDefaultValue(None))
    tref <- newIORef((1 to 3).map(_ => Vector(0, 0, 0)).toVector) 
  } yield new Node(label, lref, sref, tref)
}

object Console {
  def withPrompt(prompt: String): IO[Console] = IO(Console(prompt))
}

case class Console(prompt: String) {
  private val console = new ConsoleReader()
  console.setPrompt(prompt)

  def readLine: IO[String] = 
    io(rw => done(rw -> { console.readLine() }))
}

